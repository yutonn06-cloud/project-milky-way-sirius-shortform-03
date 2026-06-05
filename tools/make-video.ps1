# make-video.ps1 -- Local short-video assembler.
#
# Turns one Notion "ショート動画" entry (script + ElevenLabs audio) into a
# finished vertical 720x1280 mp4. Fully local (ffmpeg + whisper.cpp); no CapCut.
#
# Pipeline: pick a 通常速度 base clip (rotated to avoid duplicate-video detection),
# run it at 2x as the MAIN visual, splice in 1-2 short 高速 cut-aways for a
# speed-change "immersion" beat, optionally apply a random cinematic colour
# grade (variety + dedup), fit everything to the voice length, mix voice +
# ducked music, and burn sentence-wrapped captions (whisper timing + exact
# Notion text, white fill + black outline, just above centre).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/make-video.ps1            # latest entry, variant A
#   ... -File tools/make-video.ps1 -Variant both
#   ... -File tools/make-video.ps1 -PageId <id> -SpeedInserts 2 -Cinematic on
#   ... -File tools/make-video.ps1 -AudioFile C:\v.mp3 -ScriptText "..." -NoCaption
#
# .env (repo root): NOTION_TOKEN [, NOTION_DATABASE_ID]
# Requires ffmpeg/ffprobe on PATH (or set $env:FFMPEG_DIR).
# Captions need whisper.cpp at $WhisperDir + a ggml model at $WhisperModel.
#
# NOTE: save this file UTF-8 *with BOM* (Windows PowerShell 5.1 reads .ps1 as
# ANSI otherwise and mangles the Japanese folder/property literals).

[CmdletBinding()]
param(
    [string]$PageId,
    [ValidateSet("A","B","both")] [string]$Variant = "A",
    [ValidateSet("通常速度","高速")] [string]$Pool = "通常速度",   # main pool
    [string]$AudioFile,
    [string]$ScriptText,
    [string]$MaterialsRoot = "C:\Users\yuton\OneDrive\Desktop\編集済みサンプル素材集",
    [string]$MusicRoot     = "C:\Users\yuton\OneDrive\Desktop\Music\Sirius",
    [string]$OutDir        = "C:\Users\yuton\OneDrive\Desktop\自動生成動画",
    [double]$MusicVolume   = 0.18,
    [int]$SpeedInserts     = -1,             # -1 = auto (random 0-2); 0 = none; N = fixed
    [ValidateSet("auto","on","off")] [string]$Cinematic = "auto",
    [string]$WhisperDir    = "C:\Users\yuton\whisper-cpp\Release",
    [string]$WhisperModel  = "C:\Users\yuton\whisper-cpp\models\ggml-small.bin",
    [string]$CaptionFont   = "Meiryo",
    [int]$CaptionFontSize  = 58,
    [int]$CaptionMarginLR  = 60,             # side margins (720 wide) -> controls wrap width
    [int]$CaptionMarginV   = 540,            # distance above bottom -> ~just above centre
    [switch]$NoCaption,
    [switch]$KeepIntermediate
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $repoRoot ".tmp"
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp | Out-Null }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# --- resolve ffmpeg/ffprobe ---
function Resolve-Tool($name) {
    if ($env:FFMPEG_DIR) { $p = Join-Path $env:FFMPEG_DIR "$name.exe"; if (Test-Path $p) { return $p } }
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw "$name not found on PATH (set `$env:FFMPEG_DIR)."
}
$ffmpeg  = Resolve-Tool "ffmpeg"
$ffprobe = Resolve-Tool "ffprobe"

function Get-Duration($file) {
    $d = & $ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$file"
    return [double]$d
}

# --- .env (for Notion) ---
function Import-DotEnv {
    $envFile = Join-Path $repoRoot ".env"
    if (-not (Test-Path $envFile)) { throw "Missing .env at $envFile" }
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            Set-Item "Env:$($Matches[1])" ($Matches[2].Trim('"').Trim("'"))
        }
    }
}

function Invoke-NotionQuery {
    $headers = @{ "Authorization" = "Bearer $($env:NOTION_TOKEN)"; "Notion-Version" = "2022-06-28" }
    $dbId = $env:NOTION_DATABASE_ID
    if (-not $dbId) { $dbId = "087eff43-caa5-41ff-944e-7982f68faef8" }
    $bodyObj = @{
        filter    = @{ property = "投稿先"; select = @{ equals = "ショート動画" } }
        sorts     = @(@{ timestamp = "created_time"; direction = "descending" })
        page_size = 10
    }
    $body  = $bodyObj | ConvertTo-Json -Depth 6
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $r = Invoke-RestMethod -Uri "https://api.notion.com/v1/databases/$dbId/query" -Method Post `
            -Headers $headers -Body $bytes -ContentType "application/json; charset=utf-8"
    return $r.results
}

function Get-PageById($id) {
    $headers = @{ "Authorization" = "Bearer $($env:NOTION_TOKEN)"; "Notion-Version" = "2022-06-28" }
    $clean = $id -replace '-', ''
    return Invoke-RestMethod -Uri "https://api.notion.com/v1/pages/$clean" -Method Get -Headers $headers
}

function Get-RichText($prop) {
    if (-not $prop) { return "" }
    if ($prop.rich_text) { return ($prop.rich_text | ForEach-Object { $_.plain_text }) -join "" }
    if ($prop.title)     { return ($prop.title     | ForEach-Object { $_.plain_text }) -join "" }
    return ""
}

# --- base-clip rotation: avoid reusing the same (file, 60s offset bucket) ---
function Select-BaseClip($poolDir, $needSeconds) {
    $statePath = Join-Path $MaterialsRoot ".rotation-state.json"
    $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }
    $used = @{}
    if ($state -and $state.used) { foreach ($k in $state.used) { $used[$k] = $true } }

    $clips = Get-ChildItem -LiteralPath $poolDir -Filter *.mp4 -File | Sort-Object Name
    if (-not $clips) { throw "No clips in $poolDir" }

    function Get-Candidates($usedMap) {
        $cands = New-Object System.Collections.ArrayList
        foreach ($clip in $clips) {
            $dur = Get-Duration $clip.FullName
            $maxStart = [int][math]::Floor($dur - $needSeconds)
            if ($maxStart -lt 0) { continue }
            for ($b = 0; $b -le $maxStart; $b += 60) {
                $key = "$($clip.Name)#$b"
                if (-not $usedMap.ContainsKey($key)) { [void]$cands.Add(@{ File=$clip.FullName; Name=$clip.Name; Offset=$b; Key=$key }) }
            }
        }
        return $cands
    }
    $candidates = Get-Candidates $used
    if ($candidates.Count -eq 0) {
        Write-Host "  rotation exhausted -- resetting state."
        $used = @{}; $candidates = Get-Candidates $used
    }
    $pick = $candidates | Get-Random
    $clipDur = Get-Duration $pick.File
    $maxJitter = [math]::Max(0, [math]::Min(59, [int]($clipDur - $needSeconds - $pick.Offset)))
    $jitter = if ($maxJitter -gt 0) { Get-Random -Minimum 0 -Maximum $maxJitter } else { 0 }
    $pick.Start = $pick.Offset + $jitter

    $newUsed = @($used.Keys) + @($pick.Key) | Select-Object -Unique
    @{ used = $newUsed; updated = (Get-Date).ToString("o") } | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
    return $pick
}

# --- plan the visual timeline: 通常速度 main (2x) + 高速 cut-away inserts (1x) ---
function Get-VideoPieces($D) {
    $normalDir = Join-Path $MaterialsRoot "通常速度"
    $fastDir   = Join-Path $MaterialsRoot "高速"

    $K = if ($SpeedInserts -ge 0) { $SpeedInserts } else { Get-Random -InputObject @(0,1,1,2) }
    if ($Pool -eq "高速" -or -not (Test-Path $fastDir)) { $K = 0 }
    $fastClips = if (Test-Path $fastDir) { Get-ChildItem -LiteralPath $fastDir -Filter *.mp4 -File } else { @() }
    if ($fastClips.Count -eq 0) { $K = 0 }

    if ($K -le 0) {
        $speed = if ($Pool -eq "高速") { 1.0 } else { 2.0 }
        $need  = [math]::Ceiling($D * $speed) + 1
        $base  = Select-BaseClip (Join-Path $MaterialsRoot $Pool) $need
        return @(@{ File=$base.File; Name=$base.Name; Start=$base.Start; OutDur=$D; Speed=$speed })
    }

    $insertDurs = @(1..$K | ForEach-Object { [math]::Round((Get-Random -Minimum 3.0 -Maximum 5.0), 2) })
    $normalTotal = [math]::Round($D - ($insertDurs | Measure-Object -Sum).Sum, 2)
    if ($normalTotal -lt ($K + 1) * 4) {
        # not enough room -> fall back to single main piece
        $need = [math]::Ceiling($D * 2) + 1
        $base = Select-BaseClip $normalDir $need
        return @(@{ File=$base.File; Name=$base.Name; Start=$base.Start; OutDur=$D; Speed=2.0 })
    }

    # split normalTotal into K+1 roughly-equal parts
    $each = [math]::Round($normalTotal / ($K + 1), 2)
    $parts = @()
    for ($i = 0; $i -lt $K; $i++) { $parts += $each }
    $parts += [math]::Round($normalTotal - $each * $K, 2)

    $need = [math]::Ceiling($normalTotal * 2) + 1
    $main = Select-BaseClip $normalDir $need

    $pieces = @()
    $cursor = [double]$main.Start
    for ($i = 0; $i -lt ($K + 1); $i++) {
        $pieces += @{ File=$main.File; Name=$main.Name; Start=[math]::Round($cursor,2); OutDur=$parts[$i]; Speed=2.0 }
        $cursor += $parts[$i] * 2
        if ($i -lt $K) {
            $fc = $fastClips | Get-Random
            $fdur = Get-Duration $fc.FullName
            $fstart = if ($fdur -gt $insertDurs[$i] + 1) { Get-Random -Minimum 0 -Maximum ([int]($fdur - $insertDurs[$i] - 1)) } else { 0 }
            $pieces += @{ File=$fc.FullName; Name=$fc.Name; Start=$fstart; OutDur=$insertDurs[$i]; Speed=1.0 }
        }
    }
    return $pieces
}

# --- captions: whisper.cpp timing + exact Notion text, broken at sentences ---
function Get-SrtSec($t) {
    if ($t -match '(\d+):(\d{2}):(\d{2})[,.](\d{3})') {
        return [int]$Matches[1]*3600 + [int]$Matches[2]*60 + [int]$Matches[3] + [double]$Matches[4]/1000
    }
    return 0.0
}
function Format-AssTime($sec) {
    if ($sec -lt 0) { $sec = 0 }
    $h  = [int][math]::Floor($sec/3600)
    $m  = [int][math]::Floor(($sec%3600)/60)
    $s  = [int][math]::Floor($sec%60)
    $cs = [int][math]::Round(($sec - [math]::Floor($sec))*100)
    if ($cs -ge 100) { $cs = 99 }
    return ("{0}:{1:D2}:{2:D2}.{3:D2}" -f $h,$m,$s,$cs)
}
# libass won't auto-wrap spaceless Japanese; pre-wrap into balanced lines (no orphans), prefer breaking after 、。
function Format-CaptionWrap($text, $maxChars) {
    $L = $text.Length
    if ($L -le $maxChars) { return $text }
    $nLines = [math]::Ceiling($L / $maxChars)
    $target = [math]::Ceiling($L / $nLines)
    $lines = New-Object System.Collections.ArrayList
    $line = ""
    foreach ($ch in $text.ToCharArray()) {
        $line += $ch
        if ($lines.Count -lt ($nLines - 1)) {
            if ($line.Length -ge $target) { [void]$lines.Add($line); $line = "" }
            elseif ($line.Length -ge ($target - 2) -and '、。！？'.Contains([string]$ch)) { [void]$lines.Add($line); $line = "" }
        }
    }
    if ($line.Length -gt 0) { [void]$lines.Add($line) }
    return ($lines -join '\N')
}

function New-CaptionAss($audioPath, $scriptText, $assPath) {
    $wcli = Join-Path $WhisperDir "whisper-cli.exe"
    if (-not (Test-Path $wcli) -or -not (Test-Path $WhisperModel)) {
        Write-Warning "  whisper not found ($wcli / $WhisperModel) -- skipping captions."
        return $null
    }
    $ErrorActionPreference = 'Continue'   # ffmpeg/whisper write progress to stderr; don't treat as fatal
    $stem = [System.IO.Path]::Combine($tmp, "cap_" + [System.IO.Path]::GetRandomFileName().Split('.')[0])
    $wav  = "$stem.wav"
    & $ffmpeg -hide_banner -loglevel error -y -i $audioPath -ar 16000 -ac 1 -c:a pcm_s16le $wav | Out-Null
    if (-not (Test-Path $wav)) { Write-Warning "  wav conversion failed -- skipping captions."; return $null }
    & $wcli -m $WhisperModel -l ja -f $wav -osrt -of $stem --no-prints 2>&1 | Out-Null
    $srt = "$stem.srt"
    if (-not (Test-Path $srt)) { Write-Warning "  whisper produced no SRT -- skipping captions."; return $null }

    # parse SRT -> whisper segments (timing + text length only; whisper text is NOT displayed)
    $wsegs = New-Object System.Collections.ArrayList
    $cur = $null; $txt = ""
    foreach ($ln in (Get-Content $srt -Encoding UTF8)) {
        if ($ln -match '(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})') {
            if ($cur) { $cur.Text = $txt; [void]$wsegs.Add($cur) }
            $cur = @{ Start=(Get-SrtSec $Matches[1]); End=(Get-SrtSec $Matches[2]); Text="" }; $txt = ""
        } elseif ($ln.Trim() -match '^\d+$') {
        } elseif ($ln.Trim() -ne "") { $txt += $ln.Trim() }
    }
    if ($cur) { $cur.Text = $txt; [void]$wsegs.Add($cur) }
    if ($wsegs.Count -eq 0) { Write-Warning "  no SRT segments -- skipping captions."; return $null }

    # whisper char->time marks (linear within each segment)
    $marks = New-Object System.Collections.ArrayList
    [void]$marks.Add(@{ Char=0; Time=$wsegs[0].Start })
    $cum = 0
    foreach ($s in $wsegs) {
        $cum += [math]::Max(1, ($s.Text -replace '\s','').Length)
        [void]$marks.Add(@{ Char=$cum; Time=$s.End })
    }
    $totalW = $cum
    $audioDur = Get-Duration $audioPath

    function Get-TimeAt($wchar) {
        if ($wchar -le $marks[0].Char) { return $marks[0].Time }
        for ($i=1; $i -lt $marks.Count; $i++) {
            if ($wchar -le $marks[$i].Char) {
                $c0=$marks[$i-1].Char; $c1=$marks[$i].Char; $t0=$marks[$i-1].Time; $t1=$marks[$i].Time
                $f = if ($c1 -gt $c0) { ($wchar - $c0)/($c1 - $c0) } else { 0 }
                return $t0 + $f*($t1 - $t0)
            }
        }
        return $marks[$marks.Count-1].Time
    }

    # known script -> phrase cues (<= ~2 lines each, tighter sync); drop trailing 出典 line
    $clean = ($scriptText -replace '出典[:：][^\r\n]*','')
    $clean = ($clean -replace '[ \t\r\n]','').Trim()
    $maxChars  = [math]::Max(7, [int][math]::Floor((720 - 2*$CaptionMarginLR) / $CaptionFontSize))
    $maxPerCue = $maxChars * 2
    $units = New-Object System.Collections.ArrayList
    $buf = ""
    foreach ($ch in $clean.ToCharArray()) {
        $buf += $ch
        $isEnd   = '。！？'.Contains([string]$ch)
        $isComma = '、'.Contains([string]$ch)
        if ($isEnd -or ($isComma -and $buf.Length -ge $maxChars) -or ($buf.Length -ge $maxPerCue)) {
            [void]$units.Add($buf); $buf = ""
        }
    }
    if ($buf.Length -gt 0) {
        if ($units.Count -gt 0 -and $buf.Length -le 4) { $units[$units.Count-1] = $units[$units.Count-1] + $buf }
        else { [void]$units.Add($buf) }
    }
    if ($units.Count -eq 0) { [void]$units.Add($clean) }

    $knownLen = $clean.Length
    $scale = if ($knownLen -gt 0) { $totalW / $knownLen } else { 1 }

    $cues = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($u in $units) {
        $uLen = $u.Length
        $startT = Get-TimeAt ($pos * $scale)
        $endT   = Get-TimeAt (($pos + $uLen) * $scale)
        $pos += $uLen
        if ($endT -le $startT) { $endT = $startT + 0.8 }
        [void]$cues.Add(@{ Start=$startT; End=$endT; Text=$u })
    }
    for ($i=1; $i -lt $cues.Count; $i++) {
        if ($cues[$i].Start -lt $cues[$i-1].End) { $cues[$i].Start = $cues[$i-1].End }
        if ($cues[$i].End -le $cues[$i].Start)   { $cues[$i].End = $cues[$i].Start + 0.6 }
    }
    if ($cues.Count -gt 0 -and $audioDur -gt 0) { $cues[$cues.Count-1].End = [math]::Max($cues[$cues.Count-1].End, $audioDur) }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[Script Info]")
    [void]$sb.AppendLine("ScriptType: v4.00+")
    [void]$sb.AppendLine("PlayResX: 720")
    [void]$sb.AppendLine("PlayResY: 1280")
    [void]$sb.AppendLine("WrapStyle: 2")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("[V4+ Styles]")
    [void]$sb.AppendLine("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding")
    [void]$sb.AppendLine("Style: Default,$CaptionFont,$CaptionFontSize,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,1,0,0,0,100,100,0,0,1,4,1,2,$CaptionMarginLR,$CaptionMarginLR,$CaptionMarginV,1")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("[Events]")
    [void]$sb.AppendLine("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
    foreach ($c in $cues) {
        $t = ($c.Text -replace '\r?\n','').Trim()
        if (-not $t) { continue }
        $t = Format-CaptionWrap $t $maxChars
        [void]$sb.AppendLine("Dialogue: 0,$(Format-AssTime $c.Start),$(Format-AssTime $c.End),Default,,0,0,0,,$t")
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($assPath, $sb.ToString(), $utf8)
    if (-not $KeepIntermediate) { Remove-Item $wav,$srt -Force -ErrorAction SilentlyContinue }
    return $assPath
}

# cinematic colour-grade looks (applied to the visual, never to the captions)
$script:CinematicLooks = @(
    "eq=contrast=1.08:saturation=1.18:gamma=0.97,vignette=PI/4.5",
    "curves=preset=increase_contrast,eq=saturation=1.12,vignette=PI/5",
    "eq=contrast=1.06:saturation=0.95:gamma=1.02,colorbalance=rs=0.06:gs=0.02:bs=-0.06,vignette=PI/5",
    "eq=contrast=1.05:saturation=1.25,colorbalance=rs=-0.04:bs=0.06,vignette=PI/5"
)

# --- one variant -> one mp4 ---
function Build-One($audioPath, $caption, $tag) {
    $videoDur = [math]::Round((Get-Duration $audioPath), 2)
    if ($videoDur -le 0) { throw "audio duration is zero: $audioPath" }

    $pieces = @(Get-VideoPieces $videoDur)
    $music  = Get-ChildItem -LiteralPath $MusicRoot -Filter *.mp3 -File -Recurse | Get-Random
    if (-not $music) { throw "No .mp3 found under $MusicRoot" }

    $useCinematic = switch ($Cinematic) { "on" { $true } "off" { $false } default { (Get-Random -Minimum 0 -Maximum 100) -lt 60 } }
    $grade = if ($useCinematic) { $script:CinematicLooks | Get-Random } else { $null }

    Write-Host ("  pieces: " + (($pieces | ForEach-Object { "$($_.Name)@$($_.Start)s/$($_.OutDur)s x$($_.Speed)" }) -join "  |  "))
    Write-Host "  music: $($music.Name)"
    Write-Host "  cinematic: $(if ($grade) { $grade } else { 'none' })"
    Write-Host "  voice: $([System.IO.Path]::GetFileName($audioPath))  dur=$($videoDur)s"

    # captions
    $assPath = $null
    if (-not $NoCaption -and $caption) {
        $safeTag = ($tag -replace '[^A-Za-z0-9_]','_')
        $assPath = New-CaptionAss $audioPath $caption (Join-Path $tmp "cap_$safeTag.ass")
        if ($assPath) { Write-Host "  captions: $assPath" }
    }

    # build inputs + filtergraph
    $inputs = @()
    $nodes  = @()
    $vlabels = @()
    for ($i = 0; $i -lt $pieces.Count; $i++) {
        $p = $pieces[$i]
        $srcDur = [math]::Round($p.OutDur * $p.Speed, 2) + 0.2
        $inputs += @("-ss", $p.Start, "-t", $srcDur, "-i", $p.File)
        $sp = "setpts=$([math]::Round(1.0/$p.Speed,4))*PTS"
        $nodes += "[$($i):v]$sp,scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,setsar=1,fps=24,trim=duration=$($p.OutDur),setpts=PTS-STARTPTS[v$i]"
        $vlabels += "[v$i]"
    }
    $nodes += "$($vlabels -join '')concat=n=$($pieces.Count):v=1:a=0[vc]"
    $cur = "[vc]"
    if ($grade) { $nodes += "$cur$grade[vg]"; $cur = "[vg]" }
    if ($assPath) {
        $assEsc = ($assPath -replace '\\','/') -replace ':','\:'
        $nodes += "$cur" + "subtitles='$assEsc'[v]"; $cur = "[v]"
    }
    if ($cur -ne "[v]") { $nodes += "$cur" + "null[v]" }

    $vi = $pieces.Count; $mi = $pieces.Count + 1
    $inputs += @("-i", $audioPath)
    $inputs += @("-stream_loop", "-1", "-i", $music.FullName)
    $nodes += "[$($vi):a]volume=1.0,aformat=channel_layouts=stereo[vo]"
    $nodes += "[$($mi):a]volume=$MusicVolume,aformat=channel_layouts=stereo[mus]"
    $nodes += "[vo][mus]amix=inputs=2:duration=first:dropout_transition=0,dynaudnorm[a]"
    $filter = $nodes -join ";"

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $OutDir "auto_${tag}_${stamp}.mp4"
    $ffArgs = @("-y") + $inputs + @(
        "-filter_complex", $filter,
        "-map", "[v]", "-map", "[a]",
        "-t", $videoDur,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        $outFile
    )
    Write-Host "  ffmpeg assembling -> $outFile"
    $ErrorActionPreference = 'Continue'
    & $ffmpeg -hide_banner -loglevel error @ffArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }

    Write-Host "  DONE: $outFile  ($([math]::Round((Get-Item $outFile).Length/1MB,1)) MB)"
    return $outFile
}

# --- resolve inputs (Notion or explicit) ---
$jobs = @()
if ($AudioFile) {
    if (-not (Test-Path $AudioFile)) { throw "AudioFile not found: $AudioFile" }
    $jobs += @{ Audio = $AudioFile; Caption = $ScriptText; Tag = "manual" }
} else {
    Import-DotEnv
    $page = if ($PageId) { Get-PageById $PageId } else { (Invoke-NotionQuery)[0] }
    if (-not $page) { throw "No ショート動画 entry found." }
    $num = Get-RichText $page.properties.'原文番号'
    Write-Host "Notion entry: $num ($($page.id))"
    $variants = if ($Variant -eq "both") { @("A","B") } else { @($Variant) }
    foreach ($v in $variants) {
        $url  = if ($v -eq "A") { $page.properties.'音声URL_A'.url } else { $page.properties.'音声URL_B'.url }
        $text = if ($v -eq "A") { Get-RichText $page.properties.'リライト本文' } else { Get-RichText $page.properties.'リライト本文B' }
        if (-not $url) { Write-Warning "variant $v has no 音声URL -- skipping"; continue }
        $dl = Join-Path $tmp "voice_$v.mp3"
        Write-Host "Downloading audio $($v): $url"
        Invoke-WebRequest -Uri $url -OutFile $dl -UseBasicParsing
        $jobs += @{ Audio = $dl; Caption = $text; Tag = "$($num)_$v" }
    }
}

$results = @()
foreach ($j in $jobs) {
    Write-Host "--- building $($j.Tag) ---"
    $results += Build-One $j.Audio $j.Caption $j.Tag
}
Write-Host "==="
Write-Host "Produced $($results.Count) file(s):"
$results | ForEach-Object { Write-Host "  $_" }

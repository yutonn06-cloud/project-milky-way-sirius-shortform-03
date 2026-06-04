# make-video.ps1 -- Local short-video assembler.
#
# Turns one Notion "ショート動画" entry (script + ElevenLabs audio) into a
# finished vertical 720x1280 mp4: picks a random base clip (rotated so each
# post differs -> avoids duplicate-video detection), speeds it up, fits it to
# the voice length, mixes voice + ducked background music, and burns captions
# (whisper.cpp for timing + the exact Notion script text for accuracy).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/make-video.ps1            # latest entry, variant A
#   powershell ... -File tools/make-video.ps1 -Variant B
#   powershell ... -File tools/make-video.ps1 -PageId <id> -Variant both
#   powershell ... -File tools/make-video.ps1 -Pool 高速 -AudioFile C:\v.mp3 -ScriptText "..."
#   powershell ... -File tools/make-video.ps1 -NoCaption        # skip captions
#
# .env (repo root): NOTION_TOKEN [, NOTION_DATABASE_ID]
# Requires ffmpeg/ffprobe on PATH (or set $env:FFMPEG_DIR).
# Captions need whisper.cpp at $WhisperDir + a ggml model at $WhisperModel.
#
# NOTE: this file MUST be saved UTF-8 with BOM (Windows PowerShell 5.1 reads
# .ps1 as ANSI otherwise and mangles the Japanese folder/property literals).

[CmdletBinding()]
param(
    [string]$PageId,                       # specific Notion page; default = latest ショート動画
    [ValidateSet("A","B","both")] [string]$Variant = "A",
    [ValidateSet("通常速度","高速")] [string]$Pool = "通常速度",
    [string]$AudioFile,                    # bypass Notion: use this mp3 directly
    [string]$ScriptText,                   # bypass Notion: caption text (with -AudioFile)
    [string]$MaterialsRoot = "C:\Users\yuton\OneDrive\Desktop\編集済みサンプル素材集",
    [string]$MusicRoot     = "C:\Users\yuton\OneDrive\Desktop\Mureka",
    [string]$OutDir        = "C:\Users\yuton\OneDrive\Desktop\自動生成動画",
    [double]$MusicVolume   = 0.18,
    [string]$WhisperDir    = "C:\Users\yuton\whisper-cpp\Release",
    [string]$WhisperModel  = "C:\Users\yuton\whisper-cpp\models\ggml-small.bin",
    [string]$CaptionFont   = "Meiryo",
    [int]$CaptionFontSize  = 48,
    [int]$CaptionMarginV   = 420,           # caption distance above bottom (in 720x1280 space)
    [switch]$NoCaption,                     # skip the whisper caption step
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

# --- base-clip rotation: avoid reusing the same (file, offset bucket) ---
function Select-BaseClip($poolDir, $needSeconds) {
    $statePath = Join-Path $MaterialsRoot ".rotation-state.json"
    $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }
    $used = @{}
    if ($state -and $state.used) { foreach ($k in $state.used) { $used[$k] = $true } }

    $clips = Get-ChildItem -LiteralPath $poolDir -Filter *.mp4 -File | Sort-Object Name
    if (-not $clips) { throw "No clips in $poolDir" }

    # candidate (file, 60s-offset bucket) pairs not yet used
    function Build-Candidates($usedMap) {
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
    $candidates = Build-Candidates $used
    if ($candidates.Count -eq 0) {
        Write-Host "  rotation exhausted -- resetting state."
        $used = @{}; $candidates = Build-Candidates $used
    }
    $pick = $candidates | Get-Random
    # jitter within the 60s bucket so consecutive picks of the same bucket differ
    $clipDur = Get-Duration $pick.File
    $maxJitter = [math]::Max(0, [math]::Min(59, [int]($clipDur - $needSeconds - $pick.Offset)))
    $jitter = if ($maxJitter -gt 0) { Get-Random -Minimum 0 -Maximum $maxJitter } else { 0 }
    $pick.Start = $pick.Offset + $jitter

    $newUsed = @($used.Keys) + @($pick.Key) | Select-Object -Unique
    @{ used = $newUsed; updated = (Get-Date).ToString("o") } | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
    return $pick
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
# libass does not auto-wrap spaceless Japanese; insert explicit \N breaks (prefer after 、。)
function Format-CaptionWrap($text, $maxChars) {
    if ($text.Length -le $maxChars) { return $text }
    $lines = New-Object System.Collections.ArrayList
    $line = ""
    foreach ($ch in $text.ToCharArray()) {
        $line += $ch
        $brk = $false
        if ($line.Length -ge $maxChars) { $brk = $true }
        elseif ($line.Length -ge ($maxChars-3) -and '、。！？'.Contains([string]$ch)) { $brk = $true }
        if ($brk) { [void]$lines.Add($line); $line = "" }
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
    # ffmpeg/whisper write progress to stderr; under EAP=Stop that aborts -- relax locally (function scope)
    $ErrorActionPreference = 'Continue'
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
            # index line -- ignore
        } elseif ($ln.Trim() -ne "") { $txt += $ln.Trim() }
    }
    if ($cur) { $cur.Text = $txt; [void]$wsegs.Add($cur) }
    if ($wsegs.Count -eq 0) { Write-Warning "  no SRT segments -- skipping captions."; return $null }

    # whisper char->time marks (linear within each segment): {Char (cumulative), Time}
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

    # known script -> clean sentences (caption units); drop any trailing 出典 line
    $clean = ($scriptText -replace '出典[:：][^\r\n]*','')
    $clean = ($clean -replace '[ \t\r\n]','').Trim()
    $sentences = New-Object System.Collections.ArrayList
    $buf = ""
    foreach ($ch in $clean.ToCharArray()) {
        $buf += $ch
        if ('。！？'.Contains([string]$ch)) { [void]$sentences.Add($buf); $buf = "" }
    }
    if ($buf.Length -gt 0) { [void]$sentences.Add($buf) }
    if ($sentences.Count -eq 0) { [void]$sentences.Add($clean) }

    $knownLen = $clean.Length
    $scale = if ($knownLen -gt 0) { $totalW / $knownLen } else { 1 }

    # build cues: each sentence's start/end via the whisper timeline
    $cues = New-Object System.Collections.ArrayList
    $pos = 0
    foreach ($sent in $sentences) {
        $sLen = $sent.Length
        $startT = Get-TimeAt ($pos * $scale)
        $endT   = Get-TimeAt (($pos + $sLen) * $scale)
        $pos += $sLen
        if ($endT -le $startT) { $endT = $startT + 1.0 }
        [void]$cues.Add(@{ Start=$startT; End=$endT; Text=$sent })
    }
    # enforce monotonic, non-overlapping; clamp last to audio end
    for ($i=1; $i -lt $cues.Count; $i++) {
        if ($cues[$i].Start -lt $cues[$i-1].End) { $cues[$i].Start = $cues[$i-1].End }
        if ($cues[$i].End -le $cues[$i].Start)   { $cues[$i].End = $cues[$i].Start + 0.8 }
    }
    if ($cues.Count -gt 0 -and $audioDur -gt 0) { $cues[$cues.Count-1].End = [math]::Max($cues[$cues.Count-1].End, $audioDur) }

    # write ASS (720x1280 space; white fill + thick black outline; bottom-center, lifted)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[Script Info]")
    [void]$sb.AppendLine("ScriptType: v4.00+")
    [void]$sb.AppendLine("PlayResX: 720")
    [void]$sb.AppendLine("PlayResY: 1280")
    [void]$sb.AppendLine("WrapStyle: 0")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("[V4+ Styles]")
    [void]$sb.AppendLine("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding")
    [void]$sb.AppendLine("Style: Default,$CaptionFont,$CaptionFontSize,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,1,0,0,0,100,100,0,0,1,4,0,2,60,60,$CaptionMarginV,1")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("[Events]")
    [void]$sb.AppendLine("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
    $maxChars = [math]::Max(8, [int][math]::Floor(700 / $CaptionFontSize))
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

# --- one variant -> one mp4 ---
function Build-One($audioPath, $caption, $tag) {
    $videoDur = [math]::Round((Get-Duration $audioPath), 2)
    if ($videoDur -le 0) { throw "audio duration is zero: $audioPath" }
    $speed = if ($Pool -eq "高速") { 1.0 } else { 2.0 }
    $needSrc = [math]::Ceiling($videoDur * $speed) + 1

    $poolDir = Join-Path $MaterialsRoot $Pool
    $base = Select-BaseClip $poolDir $needSrc
    $music = Get-ChildItem -LiteralPath $MusicRoot -Filter *.mp3 -File | Get-Random

    Write-Host "  base : $($base.Name) @ $($base.Start)s  (speed x$speed, src $($needSrc)s)"
    Write-Host "  music: $($music.Name)"
    Write-Host "  voice: $([System.IO.Path]::GetFileName($audioPath))  dur=$($videoDur)s"

    # captions -> ASS (burned into the video chain)
    $assPath = $null
    if (-not $NoCaption -and $caption) {
        $safeTag = ($tag -replace '[^A-Za-z0-9_]','_')
        $assPath = New-CaptionAss $audioPath $caption (Join-Path $tmp "cap_$safeTag.ass")
        if ($assPath) { Write-Host "  captions: $assPath" }
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $OutDir "auto_${tag}_${stamp}.mp4"

    $setpts = "setpts=$([math]::Round(1.0/$speed,4))*PTS"
    $vchain = "[0:v]$setpts,scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,fps=24,setsar=1"
    if ($assPath) {
        $assEsc = ($assPath -replace '\\','/') -replace ':','\:'
        $vchain += ",subtitles='$assEsc'"
    }
    $vf = "$vchain[v]"
    $af = "[2:a]volume=$MusicVolume,aformat=channel_layouts=stereo[mus];" +
          "[1:a]volume=1.0,aformat=channel_layouts=stereo[vo];" +
          "[vo][mus]amix=inputs=2:duration=first:dropout_transition=0,dynaudnorm[a]"

    $ffArgs = @(
        "-y",
        "-ss", $base.Start, "-t", $needSrc, "-i", $base.File,
        "-i", $audioPath,
        "-stream_loop", "-1", "-i", $music.FullName,
        "-filter_complex", "$vf;$af",
        "-map", "[v]", "-map", "[a]",
        "-t", $videoDur,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        $outFile
    )
    Write-Host "  ffmpeg assembling -> $outFile"
    $ErrorActionPreference = 'Continue'   # libass/ffmpeg may warn to stderr; check exit code instead
    & $ffmpeg -hide_banner -loglevel error @ffArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }

    Write-Host "  DONE: $outFile  ($([math]::Round((Get-Item $outFile).Length/1MB,1)) MB)"
    return $outFile
}

# --- resolve inputs (Notion or explicit) ---
$jobs = @()  # each: @{ Audio=...; Caption=...; Tag=... }

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

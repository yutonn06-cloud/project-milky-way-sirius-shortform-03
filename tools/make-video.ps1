# make-video.ps1 -- Local short-video assembler.
#
# Turns one Notion "ショート動画" entry (script + ElevenLabs audio) into a
# finished vertical 720x1280 mp4. Fully local (ffmpeg + whisper.cpp); no CapCut.
#
# Pipeline: pick a 通常速度 base clip (rotated to avoid duplicate-video detection),
# play it at NORMAL 1x as the MAIN visual (occasionally a little faster for dedup),
# splice 1-2 short 高速 cut-aways (placed in the LATTER half) for a speed-change
# "immersion" beat, optionally apply a random cinematic colour grade, fit to the
# voice length, mix voice + ducked music, and burn sentence-wrapped captions
# (whisper timing + exact Notion text, white fill + black outline, just above centre).
# NSFW: only footage that scans clean is used (detected nudity is excluded; fail-closed).
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
# NSFW gate (ON by default, FAIL-CLOSED): needs `py` + tools/nsfw-scan.py
#   (pip install nudenet onnxruntime opencv-python-headless). Scans every
#   clip segment; nudity -> re-plan; can't scan -> abort. -NoNsfwScan bypasses.
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
    [double]$NsfwThreshold = 0.25,           # nudity-detection score threshold (lower = stricter)
    [switch]$NoNsfwScan,                     # DANGER: disable the nudity gate (off by default = gate ON)
    [string]$WhisperDir    = "C:\Users\yuton\whisper-cpp\Release",
    [string]$WhisperModel  = "C:\Users\yuton\whisper-cpp\models\ggml-small.bin",
    [string]$CaptionFont   = "BIZ UDPGothic",
    [int]$CaptionFontSize  = 74,
    [int]$CaptionMarginLR  = 48,             # side margins (720 wide) -> controls wrap width
    [int]$CaptionMarginV   = 540,            # distance above bottom -> ~just above centre
    [int]$CaptionMaxLines  = 3,              # cap lines per caption (2-3)
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

# --- NSFW: scan a candidate window; only clean footage is ever used (fail-closed) ---
function Get-UnsafeFrameCount($file, $start, $dur) {
    if ($NoNsfwScan) { return 0 }
    $py = Get-Command py -ErrorAction SilentlyContinue
    $scanScript = Join-Path $PSScriptRoot "nsfw-scan.py"
    if (-not $py -or -not (Test-Path $scanScript)) { throw "[NSFW] scanner unavailable (py / nsfw-scan.py). Pass -NoNsfwScan only if you accept the risk." }
    $ErrorActionPreference = 'Continue'
    $n = [math]::Min(24, [math]::Max(6, [int][math]::Ceiling($dur / 2.0)))   # dense sampling (~every 2s) to catch brief/back nudity
    $frames = @()
    for ($k = 0; $k -lt $n; $k++) {
        $ts = $start + ($dur * ($k + 0.5) / $n)
        $fp = Join-Path $tmp ("nsfw_" + [System.IO.Path]::GetRandomFileName().Split('.')[0] + ".jpg")
        & $ffmpeg -hide_banner -loglevel error -y -ss $ts -i $file -frames:v 1 -q:v 4 $fp 2>$null | Out-Null
        if (Test-Path $fp) { $frames += $fp }
    }
    if ($frames.Count -eq 0) { throw "[NSFW] could not extract frames for scan" }
    $json = & py $scanScript --threshold $NsfwThreshold @frames 2>&1
    $code = $LASTEXITCODE
    Remove-Item $frames -Force -ErrorAction SilentlyContinue
    if ($code -eq 0) { return 0 }
    if ($code -eq 2) {
        try { $r = ($json | Select-Object -Last 1) | ConvertFrom-Json } catch { $r = $null }
        if ($r -and $r.hits) { return @($r.hits).Count } else { return 1 }
    }
    throw "[NSFW] scanner error: $json"
}
# find a clean window start in a clip: try the rotation hint, then spread starts; $null if none
function Find-CleanStart($file, $needSrc, $clipDur, $hintStart) {
    if ($NoNsfwScan) { return $hintStart }
    $maxStart = [math]::Floor($clipDur - $needSrc)
    if ($maxStart -lt 0) { return $null }
    $cands = New-Object System.Collections.ArrayList
    [void]$cands.Add([int][math]::Min($hintStart, $maxStart))
    foreach ($f in @(0.0,0.15,0.3,0.45,0.6,0.75,0.9)) { [void]$cands.Add([int]($maxStart * $f)) }
    foreach ($c in ($cands | Select-Object -Unique)) {
        if ((Get-UnsafeFrameCount $file $c $needSrc) -eq 0) { return $c }
    }
    return $null
}
# rotation pick + clean-window guarantee across several clips; throws if none clean
function Select-CleanBaseClip($poolDir, $needSrc) {
    for ($t = 0; $t -lt 5; $t++) {
        $pick = Select-BaseClip $poolDir $needSrc
        $clipDur = Get-Duration $pick.File
        $cs = Find-CleanStart $pick.File $needSrc $clipDur $pick.Start
        if ($null -ne $cs) { return @{ File=$pick.File; Name=$pick.Name; Start=$cs } }
        Write-Warning "  [NSFW] $($pick.Name): no clean $([int]$needSrc)s window -- trying another clip ($($t+1)/5)"
    }
    throw "[NSFW] no clean window in $poolDir after 5 clips -- aborting (review the pool)."
}
# clean short window from the 高速 pool for one insert
function Select-CleanFast($fastClips, $dur) {
    $tries = [math]::Max(4, [math]::Min(10, $fastClips.Count * 2))
    for ($t = 0; $t -lt $tries; $t++) {
        $fc = $fastClips | Get-Random
        $fdur = Get-Duration $fc.FullName
        $need = $dur + 0.5
        if ($fdur -lt $need) { continue }
        $hint = Get-Random -Minimum 0 -Maximum ([int]($fdur - $need) + 1)
        $cs = Find-CleanStart $fc.FullName $need $fdur $hint
        if ($null -ne $cs) { return @{ File=$fc.FullName; Name=$fc.Name; Start=$cs } }
    }
    throw "[NSFW] no clean 高速 insert window -- aborting (review the 高速 pool)."
}

# --- plan the visual timeline: 通常速度 main (1x, occasionally faster) + 高速 inserts (1x), inserts biased late ---
function Get-VideoPieces($D) {
    $normalDir = Join-Path $MaterialsRoot "通常速度"
    $fastDir   = Join-Path $MaterialsRoot "高速"

    if ($Pool -eq "高速") {
        $need = [math]::Ceiling($D) + 1
        $b = Select-CleanBaseClip $fastDir $need
        return @(@{ File=$b.File; Name=$b.Name; Start=$b.Start; OutDur=$D; Speed=1.0; Kind='main' })
    }

    $K = if ($SpeedInserts -ge 0) { $SpeedInserts } else { Get-Random -InputObject @(0,1,1,2) }
    $fastClips = if (Test-Path $fastDir) { @(Get-ChildItem -LiteralPath $fastDir -Filter *.mp4 -File) } else { @() }
    if ($fastClips.Count -eq 0) { $K = 0 }

    # 通常速度 is normally left at 1x; only occasionally sped up a little (dedup variety)
    $mainSpeed = if ((Get-Random -Minimum 0 -Maximum 100) -lt 25) { Get-Random -InputObject @(1.25,1.5) } else { 1.0 }

    $insertDurs = @()
    if ($K -gt 0) { $insertDurs = @(1..$K | ForEach-Object { [math]::Round((Get-Random -Minimum 3.0 -Maximum 5.0), 2) }) }
    $mainOut = [math]::Round($D - ($insertDurs | Measure-Object -Sum).Sum, 2)
    if ($K -gt 0 -and $mainOut -lt ($K + 1) * 5) { $K = 0; $insertDurs = @(); $mainOut = $D }

    $mainSrcNeed = [math]::Ceiling($mainOut * $mainSpeed) + 1
    $main = Select-CleanBaseClip $normalDir $mainSrcNeed

    if ($K -le 0) {
        return @(@{ File=$main.File; Name=$main.Name; Start=$main.Start; OutDur=$mainOut; Speed=$mainSpeed; Kind='main' })
    }

    # late-biased insert output positions in [0.5D, 0.85D]
    $targets = @()
    for ($i = 1; $i -le $K; $i++) {
        $frac = 0.5 + 0.35 * (($i - 0.5) / $K)
        $jit  = (Get-Random -Minimum -20 -Maximum 20) / 1000.0
        $targets += [math]::Round($D * [math]::Min(0.9, [math]::Max(0.45, $frac + $jit)), 2)
    }
    $targets = @($targets | Sort-Object)

    # derive main-part output sizes so inserts land on the targets
    $mainParts = @()
    $prevCum = 0.0; $cumIns = 0.0
    for ($i = 0; $i -lt $K; $i++) {
        $cum  = $targets[$i] - $cumIns
        $part = [math]::Round($cum - $prevCum, 2)
        if ($part -lt 4) { $part = 4 }
        $mainParts += $part
        $prevCum += $part
        $cumIns  += $insertDurs[$i]
    }
    $last = [math]::Round($mainOut - ($mainParts | Measure-Object -Sum).Sum, 2)
    if ($last -lt 4) {
        $each = [math]::Round($mainOut / ($K + 1), 2)
        $mainParts = @(); for ($i = 0; $i -lt $K; $i++) { $mainParts += $each }
        $last = [math]::Round($mainOut - $each * $K, 2)
    }
    $mainParts += $last

    $pieces = @()
    $cursor = [double]$main.Start
    for ($i = 0; $i -lt ($K + 1); $i++) {
        $pieces += @{ File=$main.File; Name=$main.Name; Start=[math]::Round($cursor,2); OutDur=$mainParts[$i]; Speed=$mainSpeed; Kind='main' }
        $cursor += $mainParts[$i] * $mainSpeed
        if ($i -lt $K) {
            $f = Select-CleanFast $fastClips $insertDurs[$i]
            $pieces += @{ File=$f.File; Name=$f.Name; Start=$f.Start; OutDur=$insertDurs[$i]; Speed=1.0; Kind='insert' }
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
# libass won't auto-wrap spaceless Japanese. Wrap into lines breaking ONLY at
# natural boundaries: punctuation (、。！？) first, else after a particle
# (は/が/を/に/で/と/…), so words like 統計 are never split. Hard-break only as
# a last resort. Capped at $maxLines.
function Get-WrapPoint($s, $limit) {
    $lim = [math]::Min($limit, $s.Length)
    # 1) latest punctuation at/under the limit
    for ($i = $lim; $i -ge 2; $i--) { if ('、。！？・'.Contains([string]$s[$i-1])) { return $i } }
    # 2) latest particle (break AFTER it), not too early on the line
    $floor = [math]::Max(2, [int][math]::Ceiling($lim/2))
    for ($i = $lim; $i -ge $floor; $i--) { if ('はがをにでとへものやかねよわばずるたぐ'.Contains([string]$s[$i-1])) { return $i } }
    # 3) hard break (rare)
    return $lim
}
function Format-CaptionWrap($text, $maxChars, $maxLines) {
    if ($text.Length -le $maxChars) { return $text }
    # balance into roughly-equal lines (avoids a long line + tiny tail)
    $nLines = [math]::Min($maxLines, [math]::Ceiling($text.Length / $maxChars))
    $target = [math]::Ceiling($text.Length / $nLines)
    $lines = New-Object System.Collections.ArrayList
    $s = $text
    while ($lines.Count -lt ($nLines - 1) -and $s.Length -gt $target) {
        $bp = Get-WrapPoint $s ([math]::Min($maxChars, $target + 2))
        if ($bp -lt 2) { $bp = [math]::Min($maxChars, $s.Length) }
        [void]$lines.Add($s.Substring(0, $bp))
        $s = $s.Substring($bp)
    }
    [void]$lines.Add($s)
    # fold a tiny orphan tail (<=2 chars, e.g. "た。") back onto the previous line
    while ($lines.Count -ge 2 -and $lines[$lines.Count-1].Length -le 2) {
        $lines[$lines.Count-2] = $lines[$lines.Count-2] + $lines[$lines.Count-1]
        $lines.RemoveAt($lines.Count-1)
    }
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

    $audioDur = Get-Duration $audioPath

    # known script (clean, no 出典 line)
    $clean = ($scriptText -replace '出典[:：][^\r\n]*','')
    $clean = ($clean -replace '[ \t\r\n]','').Trim()
    $knownLen = $clean.Length
    $maxChars = [math]::Max(6, [int][math]::Floor((720 - 2*$CaptionMarginLR) / $CaptionFontSize))

    # VOICE-ALIGNED captions: whisper SEGMENT boundaries are the pauses in the spoken
    # audio, so caption times follow them. The known text is mapped onto segments
    # (proportional to each segment's whisper-text length, snapped to a natural
    # boundary), then each segment's text is sub-split into clean phrase units
    # (<= maxLines) and given a proportional slice of the segment's time -- so long
    # phrases like 「けれど、」get their own beat while staying in sync with the voice.
    $segLens = @($wsegs | ForEach-Object { [math]::Max(1, ($_.Text -replace '\s','').Length) })
    $totalSeg = ($segLens | Measure-Object -Sum).Sum
    $cap = $maxChars * $CaptionMaxLines
    function Get-SnapIndex([int]$target) {
        if ($target -le 0) { return 0 }
        if ($target -ge $knownLen) { return $knownLen }
        for ($r = 0; $r -le 5; $r++) {
            foreach ($idx in @(($target + $r), ($target - $r))) {
                if ($idx -ge 1 -and $idx -le $knownLen -and '。、！？'.Contains([string]$clean[$idx-1])) { return $idx }
            }
        }
        for ($r = 0; $r -le 5; $r++) {
            foreach ($idx in @(($target + $r), ($target - $r))) {
                if ($idx -ge 1 -and $idx -le $knownLen -and 'はがをにでとへものやかねよわ'.Contains([string]$clean[$idx-1])) { return $idx }
            }
        }
        return $target
    }
    function Split-IntoUnits([string]$t) {
        $clauses = New-Object System.Collections.ArrayList; $b = ""
        foreach ($c in $t.ToCharArray()) { $b += $c; if ('、。！？'.Contains([string]$c)) { [void]$clauses.Add($b); $b = "" } }
        if ($b.Length -gt 0) { [void]$clauses.Add($b) }
        $u = New-Object System.Collections.ArrayList; $acc = ""
        foreach ($cl in $clauses) {
            if ($acc -ne "" -and ($acc.Length + $cl.Length) -gt $cap) { [void]$u.Add($acc); $acc = "" }
            $acc += $cl
            if ($acc.Length -ge $cap) { [void]$u.Add($acc); $acc = "" }
        }
        if ($acc.Length -gt 0) { [void]$u.Add($acc) }
        if ($u.Count -eq 0) { [void]$u.Add($t) }
        return $u.ToArray()
    }
    $cues = New-Object System.Collections.ArrayList
    $cum = 0; $prevIdx = 0
    for ($i = 0; $i -lt $wsegs.Count; $i++) {
        $cum += $segLens[$i]
        if ($i -eq $wsegs.Count - 1) { $idx = $knownLen } else { $idx = Get-SnapIndex ([int][math]::Round($knownLen * $cum / $totalSeg)) }
        if ($idx -lt $prevIdx) { $idx = $prevIdx }
        if ($idx -gt $knownLen) { $idx = $knownLen }
        $segText = $clean.Substring($prevIdx, $idx - $prevIdx)
        $prevIdx = $idx
        if ($segText.Trim().Length -eq 0) { continue }
        $s = [double]$wsegs[$i].Start; $e = [double]$wsegs[$i].End
        if ($segText.Length -le $cap) {
            # one caption per voice segment -> stable (no flashing), still voice-aligned
            [void]$cues.Add(@{ Start=$s; End=$e; Text=$segText })
        } else {
            # long segment: split at 。、 and give each piece a proportional slice of the segment time
            $units = @(Split-IntoUnits $segText)
            $segChars = [math]::Max(1, $segText.Length)
            $cur = $s
            for ($j = 0; $j -lt $units.Count; $j++) {
                [void]$cues.Add(@{ Start=$cur; End=$e; Text=$units[$j] })
                $cur = [math]::Round($cur + ($e - $s) * ($units[$j].Length / $segChars), 3)
            }
        }
    }
    if ($prevIdx -lt $knownLen -and $cues.Count -gt 0) {
        $cues[$cues.Count-1].Text = $cues[$cues.Count-1].Text + $clean.Substring($prevIdx)
    } elseif ($cues.Count -eq 0) {
        [void]$cues.Add(@{ Start=0.0; End=$audioDur; Text=$clean })
    }
    # hold each caption until the next one starts (no flicker in pauses)
    for ($i = 0; $i -lt $cues.Count; $i++) {
        if ($i -lt $cues.Count - 1) { $cues[$i].End = $cues[$i+1].Start }
        if ($cues[$i].End -le $cues[$i].Start) { $cues[$i].End = $cues[$i].Start + 0.5 }
    }
    # merge too-short / too-brief captions into a neighbor (kills 「もう」-alone flashing); keep <= cap
    $minChars = 6; $minDur = 1.1
    $j = 0
    while ($cues.Count -gt 1 -and $j -lt $cues.Count) {
        $isShort = ($cues[$j].Text.Length -lt $minChars) -or (($cues[$j].End - $cues[$j].Start) -lt $minDur)
        if (-not $isShort) { $j++; continue }
        $toNext = if ($j -lt $cues.Count-1) { $cues[$j].Text.Length + $cues[$j+1].Text.Length } else { 99999 }
        $toPrev = if ($j -gt 0) { $cues[$j-1].Text.Length + $cues[$j].Text.Length } else { 99999 }
        if ($toNext -le $cap -and $toNext -le $toPrev) {
            $cues[$j+1].Text = $cues[$j].Text + $cues[$j+1].Text; $cues[$j+1].Start = $cues[$j].Start; $cues.RemoveAt($j); $j = 0
        } elseif ($toPrev -le $cap) {
            $cues[$j-1].Text = $cues[$j-1].Text + $cues[$j].Text; $cues[$j-1].End = $cues[$j].End; $cues.RemoveAt($j); $j = 0
        } else { $j++ }
    }
    if ($audioDur -gt 0) { $cues[$cues.Count-1].End = [math]::Max($cues[$cues.Count-1].End, $audioDur) }

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
        $t = Format-CaptionWrap $t $maxChars $CaptionMaxLines
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

# assemble one mp4 from the planned pieces (+ optional captions). Reused for the
# caption and no-caption versions so they are identical except for the subtitles.
function Invoke-Assemble($pieces, $music, $grade, $audioPath, $assPath, $videoDur, $outFile) {
    $inputs = @(); $nodes = @(); $vlabels = @()
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
    $ffArgs = @("-y") + $inputs + @(
        "-filter_complex", $filter,
        "-map", "[v]", "-map", "[a]",
        "-t", $videoDur,
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-movflags", "+faststart",
        $outFile
    )
    Write-Host "  ffmpeg -> $outFile"
    $ErrorActionPreference = 'Continue'
    & $ffmpeg -hide_banner -loglevel error @ffArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }
    Write-Host "  DONE: $outFile  ($([math]::Round((Get-Item $outFile).Length/1MB,1)) MB)"
}

# --- one variant -> caption + no-caption mp4s ---
function Build-One($audioPath, $caption, $tag) {
    $videoDur = [math]::Round((Get-Duration $audioPath), 2)
    if ($videoDur -le 0) { throw "audio duration is zero: $audioPath" }

    # plan clips -- NSFW gate is built into selection (only clean windows are used; fail-closed)
    $pieces = @(Get-VideoPieces $videoDur)
    if ($NoNsfwScan) { Write-Warning "  [NSFW] gate DISABLED (-NoNsfwScan)" } else { Write-Host "  [NSFW] clean-window selection OK" }

    $music  = Get-ChildItem -LiteralPath $MusicRoot -Filter *.mp3 -File -Recurse | Get-Random
    if (-not $music) { throw "No .mp3 found under $MusicRoot" }

    $useCinematic = switch ($Cinematic) { "on" { $true } "off" { $false } default { (Get-Random -Minimum 0 -Maximum 100) -lt 60 } }
    $grade = if ($useCinematic) { $script:CinematicLooks | Get-Random } else { $null }

    Write-Host ("  pieces: " + (($pieces | ForEach-Object { "$($_.Name)@$($_.Start)s/$($_.OutDur)s x$($_.Speed)" }) -join "  |  "))
    # report high-speed inserts in OUTPUT-timeline coordinates
    $t0 = 0.0
    foreach ($p in $pieces) {
        if ($p.Kind -eq 'insert') {
            Write-Host ("  >> 高速インサート: {0} を 出力 {1:N1}秒〜{2:N1}秒 に {3:N1}秒挿入" -f $p.Name, $t0, ($t0 + $p.OutDur), $p.OutDur)
        }
        $t0 += $p.OutDur
    }
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

    # produce BOTH versions from the SAME footage/music/grade: captioned + no-caption
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $results = @()
    if ($assPath) {
        $capFile = Join-Path $OutDir "auto_${tag}_${stamp}.mp4"
        Invoke-Assemble $pieces $music $grade $audioPath $assPath $videoDur $capFile
        $results += $capFile
    }
    $plainFile = Join-Path $OutDir "auto_${tag}_${stamp}_字幕なし.mp4"
    Invoke-Assemble $pieces $music $grade $audioPath $null $videoDur $plainFile
    $results += $plainFile
    return $results
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

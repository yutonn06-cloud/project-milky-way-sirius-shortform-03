# make-video.ps1 -- Local short-video assembler (MVP).
#
# Turns one Notion "ショート動画" entry (script + ElevenLabs audio) into a
# finished vertical 720x1280 mp4: picks a random base clip (rotated so each
# post differs -> avoids duplicate-video detection), speeds it up, fits it to
# the voice length, and mixes voice + ducked background music.
#
# Captions are added by a later step (whisper.cpp); pass -NoCaption to skip
# (default for now -- caption integration is WIP).
#
# Usage:
#   pwsh -File tools/make-video.ps1                 # latest entry, variant A
#   pwsh -File tools/make-video.ps1 -Variant B
#   pwsh -File tools/make-video.ps1 -PageId <id> -Variant both
#   pwsh -File tools/make-video.ps1 -Pool 高速 -AudioFile C:\path\voice.mp3 -ScriptText "..."
#
# .env (repo root): NOTION_TOKEN, NOTION_DATABASE_ID
# Requires ffmpeg/ffprobe on PATH (or set $env:FFMPEG_DIR).

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
    [switch]$NoCaption,                     # MVP: default behaviour skips captions
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

    # Build candidate (file, offsetBucket) pairs not yet used; bucket = 60s grid.
    $candidates = New-Object System.Collections.ArrayList
    foreach ($clip in $clips) {
        $dur = Get-Duration $clip.FullName
        $maxStart = [int][math]::Floor($dur - $needSeconds)
        if ($maxStart -lt 0) { continue }
        for ($b = 0; $b -le $maxStart; $b += 60) {
            $key = "$($clip.Name)#$b"
            if (-not $used.ContainsKey($key)) { [void]$candidates.Add(@{ File=$clip.FullName; Name=$clip.Name; Offset=$b; Key=$key }) }
        }
    }
    if ($candidates.Count -eq 0) {
        Write-Host "  rotation exhausted -- resetting state."
        $used = @{}; $candidates = New-Object System.Collections.ArrayList
        foreach ($clip in $clips) {
            $dur = Get-Duration $clip.FullName
            $maxStart = [int][math]::Floor($dur - $needSeconds)
            if ($maxStart -lt 0) { continue }
            for ($b = 0; $b -le $maxStart; $b += 60) { [void]$candidates.Add(@{ File=$clip.FullName; Name=$clip.Name; Offset=$b; Key="$($clip.Name)#$b" }) }
        }
    }
    $pick = $candidates | Get-Random
    # jitter within the 60s bucket so consecutive picks of the same bucket differ
    $clipDur = Get-Duration $pick.File
    $maxJitter = [math]::Max(0, [math]::Min(59, [int]($clipDur - $needSeconds - $pick.Offset)))
    $jitter = if ($maxJitter -gt 0) { Get-Random -Minimum 0 -Maximum $maxJitter } else { 0 }
    $pick.Start = $pick.Offset + $jitter

    # persist
    $newUsed = @($used.Keys) + @($pick.Key) | Select-Object -Unique
    @{ used = $newUsed; updated = (Get-Date).ToString("o") } | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
    return $pick
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
    Write-Host "  voice: $([System.IO.Path]::GetFileName($audioPath))  dur=${videoDur}s"

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outFile = Join-Path $OutDir "auto_${tag}_${stamp}.mp4"

    $setpts = "setpts=$([math]::Round(1.0/$speed,4))*PTS"
    $vf = "[0:v]$setpts,scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,fps=24,setsar=1[v]"
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
    & $ffmpeg -hide_banner -loglevel error @ffArgs
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }

    if (-not $NoCaption) {
        Write-Warning "  caption step not yet wired (whisper.cpp). Run with -NoCaption or wait for the caption step."
    }
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

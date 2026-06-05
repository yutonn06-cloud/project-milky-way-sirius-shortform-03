# add-music.ps1 -- ingest newly generated BGM into the Sirius music library.
#
# Drop raw generated tracks (any filename) into the inbox under a MOOD subfolder:
#   <MusicRoot>\_inbox\<mood>\whatever.mp3
# Then run this tool. For each file it:
#   - reads the mood from the inbox subfolder name (you classify by dropping)
#   - renames to  <Prefix>_<mood>_NN.mp3  (NN continues from the library's max)
#   - moves it into the flat library (<MusicRoot>\)
#   - appends "<new> <- <original>" to _rename-map.txt (provenance)
# The tedious part (numbering / sanitising ugly Suno/Mureka names / logging) is
# automated; the only human step is dropping into the right mood folder.
#
# Per-satellite for now (User 決定 2026-06-05); structure is ready to lift into a
# shared fleet library later. make-video selects music recursively but SKIPS _inbox,
# so un-ingested drops are never used by accident.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/add-music.ps1            # ingest the inbox
#   powershell -ExecutionPolicy Bypass -File tools/add-music.ps1 -WhatIf   # preview only

[CmdletBinding()]
param(
    [string]$MusicRoot = "C:\Users\yuton\OneDrive\Desktop\Music\Sirius",
    [string]$Prefix    = "sirius",
    [string]$Inbox,                                  # default: <MusicRoot>\_inbox
    [string[]]$Extensions = @(".mp3",".wav",".m4a",".flac",".ogg"),
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ffmpeg = transcode non-mp3 drops (wav/m4a/...) into the library's mp3 convention
function Resolve-Ffmpeg {
    if ($env:FFMPEG_DIR) { $p = Join-Path $env:FFMPEG_DIR "ffmpeg.exe"; if (Test-Path $p) { return $p } }
    $c = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $fb = "C:\Users\yuton\Downloads\ffmpeg-8.0.1-essentials_build\ffmpeg-8.0.1-essentials_build\bin\ffmpeg.exe"
    if (Test-Path $fb) { return $fb }
    return $null
}
$ffmpeg = Resolve-Ffmpeg

if (-not $Inbox) { $Inbox = Join-Path $MusicRoot "_inbox" }
if (-not (Test-Path $MusicRoot)) { throw "MusicRoot not found: $MusicRoot" }
if (-not (Test-Path $Inbox)) { Write-Host "No inbox at $Inbox -- nothing to ingest."; return }

$mapPath = Join-Path $MusicRoot "_rename-map.txt"
$utf8 = New-Object System.Text.UTF8Encoding $true

function Get-NextNum([string]$mood) {
    $max = 0
    Get-ChildItem -LiteralPath $MusicRoot -Filter "$($Prefix)_$($mood)_*.mp3" -File -EA SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match "^$([regex]::Escape($Prefix))_$([regex]::Escape($mood))_(\d+)$") {
            $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n }
        }
    }
    return $max + 1
}

$added = 0; $skipped = 0; $mapLines = @()
# each mood subfolder of the inbox (skip helper files like _README.txt)
$moodDirs = Get-ChildItem -LiteralPath $Inbox -Directory -EA SilentlyContinue | Where-Object { $_.Name -notlike "_*" }
foreach ($md in $moodDirs) {
    $mood = ($md.Name.ToLower() -replace '[^a-z0-9]', '')   # sanitise mood -> safe token
    if (-not $mood) { Write-Warning "skip inbox folder '$($md.Name)' (no usable mood token)"; continue }
    $files = Get-ChildItem -LiteralPath $md.FullName -File -EA SilentlyContinue |
        Where-Object { $Extensions -contains $_.Extension.ToLower() } | Sort-Object Name
    foreach ($f in $files) {
        $num = Get-NextNum $mood
        $newName = "{0}_{1}_{2:D2}.mp3" -f $Prefix, $mood, $num
        $dest = Join-Path $MusicRoot $newName
        while (Test-Path $dest) { $num++; $newName = "{0}_{1}_{2:D2}.mp3" -f $Prefix,$mood,$num; $dest = Join-Path $MusicRoot $newName }
        $isMp3 = ($f.Extension.ToLower() -eq ".mp3")
        if ($WhatIf) {
            Write-Host ("  [WhatIf] {0}  <-  {1}{2}" -f $newName, $f.Name, $(if ($isMp3) { "" } else { " (transcode -> mp3)" }))
            $added++; continue
        }
        if ($isMp3) {
            Move-Item -LiteralPath $f.FullName -Destination $dest
        } else {
            if (-not $ffmpeg) { Write-Warning "  $($f.Name): need ffmpeg to transcode $($f.Extension) -- skip"; $skipped++; continue }
            & $ffmpeg -hide_banner -loglevel error -y -i $f.FullName -c:a libmp3lame -q:a 2 $dest 2>$null
            if (-not (Test-Path $dest)) { Write-Warning "  $($f.Name): transcode failed -- skip"; $skipped++; continue }
            Remove-Item -LiteralPath $f.FullName -Force
        }
        Write-Host "  + $newName  <-  $($f.Name)"
        $mapLines += "$newName <- $($f.Name)"
        $added++
    }
}

if (-not $WhatIf -and $mapLines.Count -gt 0) {
    $prefix = "# Sirius BGM rename map (new <- original)`r`n"
    if (Test-Path $mapPath) {
        $existing = [System.IO.File]::ReadAllText($mapPath)
        # separate from a last line that lacks a trailing newline
        $prefix = if ($existing.Length -gt 0 -and $existing[-1] -notin "`n", "`r") { "`r`n" } else { "" }
    }
    [System.IO.File]::AppendAllText($mapPath, $prefix + (($mapLines -join "`r`n") + "`r`n"), $utf8)
}

# count with bounded retry: OneDrive can briefly return an empty enumeration right
# after writes (a false 0). Post-ingest the library is non-empty, so retry until >0.
function Get-LibCount {
    for ($i = 0; $i -lt 5; $i++) {
        $n = @(Get-ChildItem -LiteralPath $MusicRoot -Filter "$($Prefix)_*.mp3" -File -EA SilentlyContinue).Count
        if ($n -gt 0 -or $added -eq 0) { return $n }
        Start-Sleep -Milliseconds 300
    }
    return $n
}
Write-Host "==="
Write-Host "Ingested $added file(s)$(if ($skipped) { ", skipped $skipped non-mp3" })$(if ($WhatIf) { ' (WhatIf -- nothing moved)' })."
Write-Host "Library now: $(Get-LibCount) tracks in $MusicRoot"

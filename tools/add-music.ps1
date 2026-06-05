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
        if ($f.Extension.ToLower() -ne ".mp3") {
            Write-Warning "  $($f.Name): not .mp3 (got $($f.Extension)) -- skip (convert manually for now)"
            $skipped++; continue
        }
        $num = Get-NextNum $mood
        $newName = "{0}_{1}_{2:D2}.mp3" -f $Prefix, $mood, $num
        $dest = Join-Path $MusicRoot $newName
        while (Test-Path $dest) { $num++; $newName = "{0}_{1}_{2:D2}.mp3" -f $Prefix,$mood,$num; $dest = Join-Path $MusicRoot $newName }
        if ($WhatIf) {
            Write-Host "  [WhatIf] $newName  <-  $($f.Name)"
        } else {
            Move-Item -LiteralPath $f.FullName -Destination $dest
            Write-Host "  + $newName  <-  $($f.Name)"
            $mapLines += "$newName <- $($f.Name)"
        }
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

Write-Host "==="
Write-Host "Ingested $added file(s)$(if ($skipped) { ", skipped $skipped non-mp3" })$(if ($WhatIf) { ' (WhatIf -- nothing moved)' })."
Write-Host "Library now: $(@(Get-ChildItem -LiteralPath $MusicRoot -Filter "$($Prefix)_*.mp3" -File -EA SilentlyContinue).Count) tracks in $MusicRoot"

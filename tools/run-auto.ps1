# run-auto.ps1 -- launcher for the scheduled Sirius auto-video buffer job.
#
# Sets FFMPEG_DIR (so the Task Scheduler context can find ffmpeg), then runs
# make-video.ps1 -Auto and tees everything to .tmp/auto-YYYYMMDD.log so each
# scheduled run is auditable. Registered to run twice daily by register-auto-task.ps1.
#
# Manual test: powershell -ExecutionPolicy Bypass -File tools/run-auto.ps1

$ErrorActionPreference = "Continue"
$here = $PSScriptRoot
$repo = Split-Path -Parent $here

# ffmpeg location (scheduled context has no FFMPEG_DIR / may lack PATH). Override
# by setting FFMPEG_DIR before launch; edit here if the ffmpeg build moves.
if (-not $env:FFMPEG_DIR) {
    $env:FFMPEG_DIR = "C:\Users\yuton\Downloads\ffmpeg-8.0.1-essentials_build\ffmpeg-8.0.1-essentials_build\bin"
}

$logDir = Join-Path $repo ".tmp"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("auto-" + (Get-Date -Format "yyyyMMdd") + ".log")
$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Log([string]$text) { [System.IO.File]::AppendAllText($log, $text + "`r`n", $utf8) }

# capture all streams as one UTF-8 block (Tee + Out-File mixed encodings -> mojibake)
Write-Log "==== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') auto run ===="
$out = & (Join-Path $here "make-video.ps1") -Auto *>&1 | Out-String
Write-Log $out
Write-Log "==== exit $LASTEXITCODE @ $(Get-Date -Format 'HH:mm:ss') ===="

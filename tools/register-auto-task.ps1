# register-auto-task.ps1 -- register the daily Sirius auto-video buffer job.
#
# Creates ONE Windows Scheduled Task "Sirius-AutoVideo" with two daily triggers
# (13:00 and 16:00 local) that run tools/run-auto.ps1 = make-video.ps1 -Auto.
# Runs as the current user, only when logged on (no admin needed). Idempotent
# (-Force replaces an existing task). Posting is 18-20:00, so done-by-then is fine;
# two triggers + the buffer mean a missed run never blocks posting.
#
# Run once:   powershell -ExecutionPolicy Bypass -File tools/register-auto-task.ps1
# Times:      -Times "13:00","16:00"   (override)
# Remove:     Unregister-ScheduledTask -TaskName Sirius-AutoVideo -Confirm:$false

param(
    [string[]]$Times = @("13:00","16:00"),
    [string]$TaskName = "Sirius-AutoVideo"
)

$ErrorActionPreference = "Stop"
$launcher = Join-Path $PSScriptRoot "run-auto.ps1"
if (-not (Test-Path $launcher)) { throw "launcher not found: $launcher" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`"" `
    -WorkingDirectory (Split-Path -Parent $PSScriptRoot)

$triggers = foreach ($t in $Times) { New-ScheduledTaskTrigger -Daily -At ([datetime]$t) }

# run as the current user, only when logged on (interactive) -> no admin / no stored password
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
    -Principal $principal -Settings $settings `
    -Description "Sirius full-auto short-video buffer: make-video.ps1 -Auto (archive 使用済み, generate cuts of newest unposted topic). 司令官は字幕なし\ から Filmora で仕上げて投稿。" `
    -Force | Out-Null

Write-Host "Registered '$TaskName' at: $($Times -join ', ')  (current user, when logged on)."
Write-Host "  -StartWhenAvailable = if the PC was off at trigger time, it runs at next wake."
Write-Host "  Run now to test:  Start-ScheduledTask -TaskName $TaskName"

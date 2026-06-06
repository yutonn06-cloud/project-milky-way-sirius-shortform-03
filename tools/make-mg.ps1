# make-mg.ps1 -- motion-graphics + music (and 音ハメ) test renderer (local ffmpeg).
#
# Goal (2026-06-06): explore MG patterns to raise immersion, and judge whether they can be
# applied to the base narration videos. Music from Music\Sirius (commercial-use cleared).
#
# Patterns:
#   ambient   -- procedural dark gradient + noise + hue drift + vignette (no audio reactivity)
#   spectrum  -- showcqt音楽スペクトラム over dark bg (AUDIO-REACTIVE = 音ハメ)
#   vscope    -- avectorscope オーブ over dark bg (AUDIO-REACTIVE = 音ハメ)
#   typo      -- kinetic タイポ (短い断片) over a subtle reactive bg
#   beatpulse -- ambient bg + white FLASH on detected beats (explicit 音ハメ; needs py+numpy)
#   overlay   -- composite an MG element (particles/light/spectrum) ONTO -BaseVideo (適用見極め用)
#
# Usage:
#   powershell -File tools\make-mg.ps1 -Pattern spectrum -Music enigmatic -Dur 18
#   powershell -File tools\make-mg.ps1 -Pattern typo -Text "気づいてしまった人へ" -Music sacred
#   powershell -File tools\make-mg.ps1 -Pattern beatpulse -Music trance
#   powershell -File tools\make-mg.ps1 -Pattern overlay -BaseVideo "<...auto_原文305...>.mp4" -MgMode light

[CmdletBinding()]
param(
    [ValidateSet("ambient","spectrum","vscope","typo","beatpulse","overlay")] [string]$Pattern = "spectrum",
    [string]$Music    = "",                  # full path, or a mood name (enigmatic/sacred/trance/...), or "" = random
    [double]$Dur      = 18.0,
    [string]$Text     = "気づいて、しまった。",
    [string]$BaseVideo = "",                 # overlay pattern: the base narration video to composite onto
    [ValidateSet("light","particles","spectrum")] [string]$MgMode = "light",  # overlay element
    [string]$OutDir   = "C:\Users\yuton\OneDrive\Desktop\自動生成動画\MG検証",
    [string]$MusicRoot = "C:\Users\yuton\OneDrive\Desktop\Music\Sirius",
    [string]$FfmpegDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path $repoRoot ".tmp"
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp | Out-Null }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

if (-not $FfmpegDir) {
    $FfmpegDir = if ($env:FFMPEG_DIR) { $env:FFMPEG_DIR } else { "C:\Users\yuton\Downloads\ffmpeg-8.0.1-essentials_build\ffmpeg-8.0.1-essentials_build\bin" }
}
$ff = Join-Path $FfmpegDir "ffmpeg.exe"
if (-not (Test-Path $ff)) { throw "ffmpeg not found: $ff" }

$fontPath = "C\:/Windows/Fonts/BIZ-UDGothicB.ttc"   # ffmpeg drawtext (escaped colon, fwd slashes)
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dark  = "vignette=PI/4.2,eq=contrast=1.06:saturation=0.92:brightness=-0.03,format=yuv420p"   # brand-dark finish

function Invoke-Ff($filter, $musicFilePath, $outFile, $extraInputs) {
    $ffArgs = @("-hide_banner","-loglevel","error","-y")
    if ($extraInputs) { $ffArgs += $extraInputs }
    $ffArgs += @("-stream_loop","-1","-i", $musicFilePath)
    $ffArgs += @("-filter_complex", $filter, "-map","[v]","-map","0:a?")
    # music is input 0 for music-only patterns
    $ffArgs += @("-t", $Dur, "-r","24","-c:v","libx264","-preset","medium","-crf","20","-pix_fmt","yuv420p",
               "-c:a","aac","-b:a","192k","-movflags","+faststart", $outFile)
    Write-Host "  ffmpeg -> $([System.IO.Path]::GetFileName($outFile))"
    & $ff @ffArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }
    Write-Host ("  DONE: {0}  ({1:N1} MB)" -f $outFile, ((Get-Item $outFile).Length/1MB))
}

# ============================ MUSIC-ONLY MG PATTERNS ============================
if ($Pattern -ne "overlay") {
    # pick music inline (full path / mood name / random)
    $allMusic = @(Get-ChildItem $MusicRoot -File -Recurse | Where-Object { $_.FullName -notmatch '\\_[^\\]*\\' -and $_.Extension -match '\.(mp3|wav|m4a|flac|ogg)$' })
    if ($allMusic.Count -eq 0) { throw "no music under $MusicRoot" }
    if ($Music -and (Test-Path -LiteralPath $Music)) {
        $musicFile = Get-Item -LiteralPath $Music
    } elseif ($Music) {
        $mm = @($allMusic | Where-Object { $_.BaseName -like "sirius_${Music}_*" })
        $musicFile = if ($mm.Count -gt 0) { $mm | Get-Random } else { $allMusic | Get-Random }
    } else {
        $musicFile = $allMusic | Get-Random
    }
    Write-Host "Pattern=$Pattern  music=$($musicFile.Name)  dur=${Dur}s"
    $out = Join-Path $OutDir "mg_${Pattern}_${stamp}.mp4"
    $bg  = "gradients=s=720x1280:c0=0x080816:c1=0x190a30:c2=0x02020a:n=3:speed=0.01"

    switch ($Pattern) {
        "ambient" {
            $filter = "$bg,noise=alls=5:allf=t,hue=H=0.05*t,gblur=sigma=1.2,$dark[v]"
            Invoke-Ff $filter $musicFile.FullName $out $null
        }
        "spectrum" {
            $filter = "[0:a]showcqt=s=720x460:fps=24:count=2:gamma=4:bar_g=1.4:sono_g=1.4,format=rgba,gblur=sigma=0.6[cqt];$bg,format=rgba[bg];[bg][cqt]overlay=0:H-h-150[v0];[v0]$dark[v]"
            Invoke-Ff $filter $musicFile.FullName $out $null
        }
        "vscope" {
            $filter = "[0:a]avectorscope=s=720x720:rate=24:zoom=1.8:draw=line:rc=80:gc=40:bc=200,format=rgba,gblur=sigma=3[av];$bg,format=rgba[bg];[bg][av]overlay=(W-w)/2:(H-h)/2[v0];[v0]$dark[v]"
            Invoke-Ff $filter $musicFile.FullName $out $null
        }
        "typo" {
            $txtFile = Join-Path $tmp "mgtext_$stamp.txt"
            [System.IO.File]::WriteAllText($txtFile, $Text, (New-Object System.Text.UTF8Encoding $false))
            $tf = ($txtFile -replace '\\','/') -replace ':','\:'
            $alpha = "if(lt(t,1.2),t/1.2,if(lt(t,$($Dur-1.2)),1,max(0,($Dur-t)/1.2)))"
            $dt = "drawtext=textfile='$tf':fontfile='$fontPath':fontcolor=white:fontsize=58:x=(w-text_w)/2:y=(h-text_h)/2:alpha='$alpha':line_spacing=18:shadowcolor=black@0.6:shadowx=2:shadowy=2"
            $filter = "[0:a]showspectrum=s=720x1280:mode=combined:color=intensity:scale=cbrt:slide=scroll:fps=24,format=rgba,colorchannelmixer=rr=0.3:gg=0.15:bb=0.5,gblur=sigma=6,eq=brightness=-0.25[sp];color=c=0x05050c:s=720x1280:r=24,format=rgba[base];[base][sp]overlay[bg0];[bg0]$dt,$dark[v]"
            Invoke-Ff $filter $musicFile.FullName $out $null
        }
        "beatpulse" {
            # 1) decode music to mono wav, 2) detect onsets (numpy), 3) flash on each beat
            $py = (Get-Command py -ErrorAction SilentlyContinue)
            if (-not $py) { throw "py not found (needed for beatpulse onset detection)" }
            $wav = Join-Path $tmp "mgbeat_$stamp.wav"
            & $ff -hide_banner -loglevel error -y -i $musicFile.FullName -ac 1 -ar 22050 -t $Dur $wav 2>&1 | Out-Null
            $beats = (& py (Join-Path $PSScriptRoot "detect-beats.py") $wav) -join ' '
            $btimes = @($beats -split '\s+' | Where-Object { $_ -match '^\d' } | ForEach-Object { [double]$_ })
            Write-Host "  beats detected: $($btimes.Count)"
            $enable = if ($btimes.Count -gt 0) { ($btimes | ForEach-Object { "between(t,$_,$([math]::Round($_+0.07,3)))" }) -join "+" } else { "0" }
            $flash = "drawbox=x=0:y=0:w=iw:h=ih:color=white@0.16:t=fill:enable='$enable'"
            $filter = "$bg,noise=alls=4:allf=t,hue=H=0.05*t,$flash,gblur=sigma=1.0,$dark[v]"
            Invoke-Ff $filter $musicFile.FullName $out $null
        }
    }
    Write-Host "Produced: $out"
    return
}

# ============================ OVERLAY ONTO BASE VIDEO (適用見極め) ============================
# Composite an MG element over an existing narration video using SCREEN blend (adds light only,
# keeps the footage). This is the "can we apply MG to the base videos?" test.
if (-not $BaseVideo -or -not (Test-Path $BaseVideo)) { throw "overlay needs -BaseVideo <path to a base mp4>" }
$baseItem = Get-Item $BaseVideo
$out = Join-Path $OutDir ("mg_overlay_" + $MgMode + "_" + $baseItem.BaseName + "_" + $stamp + ".mp4")
Write-Host "Overlay MgMode=$MgMode onto $($baseItem.Name)"

# MG element generated procedurally, blended SCREEN over the base (input 0 = base video+audio).
switch ($MgMode) {
    "light" {
        # drifting soft light blooms (additive) -- subtle, brand-dark
        $mg = "gradients=s=720x1280:c0=0x000000:c1=0x2a1640:c2=0x000000:n=3:speed=0.02,gblur=sigma=40,eq=brightness=-0.15"
    }
    "particles" {
        # sparse drifting specks via noise threshold
        $mg = "nullsrc=s=720x1280:r=24,geq=lum='if(gt(random(1)*255,253),200,0)':cb=128:cr=128,gblur=sigma=2,eq=brightness=-0.1"
    }
    "spectrum" {
        # audio-reactive spectrum from the BASE audio, faint, bottom -- 音ハメ accent
        $mg = "[0:a]showcqt=s=720x300:fps=24:count=1:bar_g=2,format=gbrp,colorchannelmixer=rr=0.4:gg=0.2:bb=0.7,gblur=sigma=1[cqtsrc];color=c=black:s=720x1280:r=24[cv];[cv][cqtsrc]overlay=0:H-h-120,eq=brightness=-0.1"
    }
}
$filter = "[0:v]scale=720:1280,setsar=1,fps=24[base];$mg[mg];[base][mg]blend=all_mode=screen:all_opacity=0.55,format=yuv420p[v]"
$ffArgs = @("-hide_banner","-loglevel","error","-y","-i", $baseItem.FullName,
          "-filter_complex", $filter, "-map","[v]","-map","0:a?",
          "-t", $Dur, "-r","24","-c:v","libx264","-preset","medium","-crf","20","-pix_fmt","yuv420p",
          "-c:a","aac","-b:a","192k","-movflags","+faststart", $out)
Write-Host "  ffmpeg -> $([System.IO.Path]::GetFileName($out))"
& $ff @ffArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }
Write-Host ("  DONE: {0}  ({1:N1} MB)" -f $out, ((Get-Item $out).Length/1MB))
Write-Host "Produced: $out"

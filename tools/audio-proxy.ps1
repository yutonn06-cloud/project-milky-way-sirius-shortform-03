# ElevenLabs audio proxy — adds xi-api-key header so URLs are browser-clickable.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\audio-proxy.ps1
#
# Then in Notion, the audio URLs are http://localhost:8765/audio/{history-item-id}.
# Click in any browser (while this script is running) → audio streams + plays inline.
#
# Auto-start at login: see README.md "Audio proxy auto-start".

$ErrorActionPreference = "Stop"
$Port = 8765

# Load .env from repo root (parent of tools/)
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot ".env"
if (-not (Test-Path $envFile)) {
    Write-Error "Missing .env at $envFile"
    exit 1
}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        Set-Item "Env:$($Matches[1])" $Matches[2]
    }
}
if (-not $env:ELEVENLABS_API_KEY) {
    Write-Error "ELEVENLABS_API_KEY missing from .env"
    exit 1
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "ElevenLabs audio proxy listening on http://localhost:$Port/"
Write-Host "Audio URL pattern: http://localhost:$Port/audio/{history-item-id}"
Write-Host "Press Ctrl+C to stop."

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        $clientAddr = $req.RemoteEndPoint.Address.ToString()
        try {
            $path = $req.Url.AbsolutePath
            Write-Host "[$([DateTime]::Now.ToString('HH:mm:ss'))] $clientAddr $($req.HttpMethod) $path"

            if ($path -match '^/audio/([A-Za-z0-9_-]+)/?$') {
                $historyId = $Matches[1]
                $upstream = "https://api.elevenlabs.io/v1/history/$historyId/audio"
                $http = [System.Net.HttpWebRequest]::Create($upstream)
                $http.Method = "GET"
                $http.Headers.Add("xi-api-key", $env:ELEVENLABS_API_KEY)
                try {
                    $upstreamResp = $http.GetResponse()
                    $res.StatusCode = 200
                    $res.ContentType = "audio/mpeg"
                    $res.AddHeader("Content-Disposition", "inline; filename=`"$historyId.mp3`"")
                    $upstreamResp.GetResponseStream().CopyTo($res.OutputStream)
                    $upstreamResp.Close()
                } catch [System.Net.WebException] {
                    $errResp = $_.Exception.Response
                    if ($errResp) {
                        $res.StatusCode = [int]$errResp.StatusCode
                        $reader = New-Object System.IO.StreamReader($errResp.GetResponseStream())
                        $body = $reader.ReadToEnd()
                    } else {
                        $res.StatusCode = 502
                        $body = $_.Exception.Message
                    }
                    $res.ContentType = "application/json; charset=utf-8"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            } elseif ($path -eq "/" -or $path -eq "/health") {
                $res.StatusCode = 200
                $res.ContentType = "text/plain; charset=utf-8"
                $body = "ElevenLabs audio proxy OK. Use /audio/{history-item-id}."
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $res.ContentType = "text/plain; charset=utf-8"
                $body = "Not found. Use /audio/{history-item-id}."
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        } catch {
            Write-Warning "Request error: $_"
            try {
                $res.StatusCode = 500
                $body = "Internal proxy error: $_"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {}
        } finally {
            try { $res.Close() } catch {}
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}

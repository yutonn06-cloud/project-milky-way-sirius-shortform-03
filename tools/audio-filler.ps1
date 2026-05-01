# Audio filler -- generates ElevenLabs audio for Notion entries missing audio URLs.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\audio-filler.ps1
#       Polls the Notion database for entries with empty 音声URL_A and fills A+B.
#
#   powershell -ExecutionPolicy Bypass -File tools\audio-filler.ps1 -PageId <id>
#       Processes a single page by ID (32 hex or UUID form).
#
# .env requirements (repo root):
#   ELEVENLABS_API_KEY=sk_...
#   ELEVENLABS_VOICE_ID=...
#   NOTION_TOKEN=secret_...           # internal integration token from notion.so/my-integrations
#   NOTION_DATABASE_ID=<32-hex>        # database_id of "Rewrite Script" (only needed for poll mode)
#
# Setup:
#   1. Create integration at https://www.notion.so/my-integrations → copy "Internal Integration Token"
#   2. On the Notion DB "Rewrite Script" page, click ⋯ → Connections → add the integration
#   3. NOTION_DATABASE_ID = the 32-hex string at the end of the DB URL (no hyphens)

[CmdletBinding()]
param(
    [string]$PageId
)

$ErrorActionPreference = "Stop"

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

$required = @("ELEVENLABS_API_KEY", "ELEVENLABS_VOICE_ID", "NOTION_TOKEN")
if (-not $PageId) { $required += "NOTION_DATABASE_ID" }
foreach ($v in $required) {
    if (-not (Get-Item "Env:$v" -ErrorAction SilentlyContinue).Value) {
        Write-Error "$v missing from .env"
        exit 1
    }
}

$apiKey  = $env:ELEVENLABS_API_KEY
$voiceId = $env:ELEVENLABS_VOICE_ID
$notion  = $env:NOTION_TOKEN
$dbId    = $env:NOTION_DATABASE_ID

$notionHeaders = @{
    "Authorization"  = "Bearer $notion"
    "Notion-Version" = "2022-06-28"
    "Content-Type"   = "application/json; charset=utf-8"
}

function Invoke-Notion {
    param([string]$Method, [string]$Url, [string]$JsonBody)
    if ($JsonBody) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $notionHeaders -Body $bytes
    }
    return Invoke-RestMethod -Method $Method -Uri $Url -Headers $notionHeaders
}

function Get-RichText($prop) {
    if (-not $prop) { return "" }
    if ($prop.rich_text) { return ($prop.rich_text | ForEach-Object { $_.plain_text }) -join "" }
    if ($prop.title)     { return ($prop.title     | ForEach-Object { $_.plain_text }) -join "" }
    return ""
}

function Get-PendingPages {
    if ($PageId) {
        $cleanId = $PageId -replace '-', ''
        $page = Invoke-Notion -Method Get -Url "https://api.notion.com/v1/pages/$cleanId"
        return @($page)
    }
    # 投稿先 == "ショート動画" のみ音声生成。X など他プラットフォームは
    # テキスト投稿のためスキップする（skill/MAIN.md の side-effect contract）。
    $bodyObj = @{
        filter    = @{
            and = @(
                @{ property = "音声URL_A"; url = @{ is_empty = $true } },
                @{ property = "投稿先"; select = @{ equals = "ショート動画" } }
            )
        }
        page_size = 50
    }
    $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
    $resp = Invoke-Notion -Method Post -Url "https://api.notion.com/v1/databases/$dbId/query" -JsonBody $body
    return $resp.results
}

function New-ElevenLabsAudio($text, $variant) {
    Write-Host "    [$variant] generating audio ($($text.Length) chars)..."
    $bodyJson = @{ text = $text; model_id = "eleven_v3" } | ConvertTo-Json -Depth 5 -Compress
    $tmpBody    = [System.IO.Path]::GetTempFileName()
    $tmpAudio   = [System.IO.Path]::GetTempFileName()
    $tmpHeaders = [System.IO.Path]::GetTempFileName()
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tmpBody, $bodyJson, $utf8)
        $url = "https://api.elevenlabs.io/v1/text-to-speech/$voiceId" + "?output_format=mp3_22050_32"
        $curlArgs = @(
            "-sS", "-D", $tmpHeaders, "-X", "POST", $url,
            "-H", "xi-api-key: $apiKey",
            "-H", "Content-Type: application/json",
            "--data-binary", "@$tmpBody",
            "--output", $tmpAudio
        )
        $stderr = & curl.exe @curlArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "curl exit $LASTEXITCODE for $variant. $stderr"
        }
        $headerLines = Get-Content $tmpHeaders
        $status = $headerLines | Select-Object -First 1
        if ($status -notmatch 'HTTP/\S+\s+2\d\d') {
            $errBody = if (Test-Path $tmpAudio) { Get-Content $tmpAudio -Raw } else { "" }
            throw "ElevenLabs $status -- $errBody"
        }
        $idLine = $headerLines | Where-Object { $_ -match '^(?i)history-item-id:\s*(\S+)' }
        if (-not $idLine) { throw "history-item-id missing from response headers ($variant)" }
        $null = $idLine -match '^(?i)history-item-id:\s*(\S+)'
        $historyId = $Matches[1]
        Write-Host "      history-item-id=$historyId"
        return $historyId
    } finally {
        Remove-Item $tmpBody, $tmpAudio, $tmpHeaders -Force -ErrorAction SilentlyContinue
    }
}

function Update-PageAudio($pageRef, $urlA, $urlB) {
    $cleanId = $pageRef -replace '-', ''
    # 音声URL_A / 音声URL_B are typed `url` -- send the raw URL, not a
    # rich_text wrapper, otherwise Notion returns 400 ("expected to be url").
    $body = @{
        properties = @{
            "音声URL_A" = @{ url = $urlA }
            "音声URL_B" = @{ url = $urlB }
        }
    } | ConvertTo-Json -Depth 10 -Compress
    $null = Invoke-Notion -Method Patch -Url "https://api.notion.com/v1/pages/$cleanId" -JsonBody $body
}

# Main
$pages = Get-PendingPages
if (-not $pages -or @($pages).Count -eq 0) {
    Write-Host "No pending entries."
    exit 0
}

$total = @($pages).Count
Write-Host "Found $total page(s) needing audio."
$success = 0
$failed = 0

foreach ($page in $pages) {
    $pageRef = $page.id
    $title = Get-RichText $page.properties.'タイトル'
    $textA = Get-RichText $page.properties.'リライト本文'
    $textB = Get-RichText $page.properties.'リライト本文B'

    Write-Host "---"
    Write-Host "Page: $title ($pageRef)"

    if (-not $textA -or -not $textB) {
        Write-Warning "  skip: missing リライト本文 or リライト本文B"
        $failed++
        continue
    }

    try {
        $idA = New-ElevenLabsAudio $textA "A"
        $idB = New-ElevenLabsAudio $textB "B"
        Update-PageAudio $pageRef "http://localhost:8765/audio/$idA" "http://localhost:8765/audio/$idB"
        Write-Host "  OK -- Notion updated."
        $success++
    } catch {
        Write-Warning "  failed: $_"
        $failed++
    }
}

Write-Host "---"
Write-Host "Done. success=$success failed=$failed total=$total"
if ($failed -gt 0) { exit 1 }

# Notion REST wrapper -- create a page in the rewrite database without going through the MCP server.
#
# Usage (file -- recommended on Windows, no shell quoting issues):
#   powershell -ExecutionPolicy Bypass -File tools\notion-create-page.ps1 -PropertiesFile path\to\props.json
#
# Usage (inline -- works in bash / pwsh 7+ where single quotes preserve content):
#   pwsh -File tools/notion-create-page.ps1 -PropertiesJson '{"タイトル":"週末が怖い","投稿先":"X",...}'
#
# Accepts a FLAT property map (name -> value). Converts to Notion's typed JSON
# according to the hardcoded schema for the rewrite database.
# POSTs to https://api.notion.com/v1/pages and prints the new page URL on stdout.
#
# Replaces: Notion MCP `notion-create-pages` tool (saves the ~20 unused MCP tool slots).
# Pattern mirrors tools/audio-filler.ps1 lines 28-67 (env loading + Invoke-RestMethod).

[CmdletBinding(DefaultParameterSetName='Inline')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Inline')]
    [string]$PropertiesJson,

    [Parameter(Mandatory=$true, ParameterSetName='File')]
    [string]$PropertiesFile
)

if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path $PropertiesFile)) {
        Write-Error "PropertiesFile not found: $PropertiesFile"
        exit 1
    }
    $PropertiesJson = [System.IO.File]::ReadAllText((Resolve-Path $PropertiesFile), [System.Text.Encoding]::UTF8)
}

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

if (-not $env:NOTION_TOKEN) {
    Write-Error "NOTION_TOKEN missing from .env"
    exit 1
}

$databaseId = "087eff43-caa5-41ff-944e-7982f68faef8"

$schema = [ordered]@{
    "タイトル"     = "title"
    "リライト本文"   = "rich_text"
    "キャプション"   = "rich_text"
    "リライト本文B"  = "rich_text"
    "投稿先"      = "select"
    "ターゲット"    = "rich_text"
    "文体"       = "rich_text"
    "原文番号"     = "rich_text"
    "ファイル名"    = "rich_text"
    "文字数"      = "number"
    "文字数B"     = "rich_text"
    "採用"       = "select"
    "ステータス"    = "select"
    "音声URL_A"  = "rich_text"
    "音声URL_B"  = "rich_text"
    "出典URL_A"  = "url"
    "出典URL_B"  = "url"
    "出典媒体"     = "rich_text"
    "メモ"       = "rich_text"
}

try {
    $flat = $PropertiesJson | ConvertFrom-Json
} catch {
    Write-Error "PropertiesJson is not valid JSON: $($_.Exception.Message)"
    exit 1
}

$typed = @{}
foreach ($prop in $flat.PSObject.Properties) {
    $name = $prop.Name
    $val  = $prop.Value
    if (-not $schema.Contains($name)) {
        Write-Warning "Unknown property '$name' -- skipped (not in DB schema)"
        continue
    }
    if ($null -eq $val -or "$val" -eq "") { continue }

    switch ($schema[$name]) {
        "title"     { $typed[$name] = @{ title     = @(@{ text = @{ content = "$val" } }) } }
        "rich_text" { $typed[$name] = @{ rich_text = @(@{ text = @{ content = "$val" } }) } }
        "select"    { $typed[$name] = @{ select    = @{ name = "$val" } } }
        "number"    { $typed[$name] = @{ number    = [double]$val } }
        "url"       { $typed[$name] = @{ url       = "$val" } }
    }
}

$payload = @{
    parent     = @{ database_id = $databaseId }
    properties = $typed
} | ConvertTo-Json -Depth 10 -Compress

$headers = @{
    "Authorization"  = "Bearer $env:NOTION_TOKEN"
    "Notion-Version" = "2022-06-28"
    "Content-Type"   = "application/json; charset=utf-8"
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$resp  = Invoke-RestMethod -Method Post -Uri "https://api.notion.com/v1/pages" -Headers $headers -Body $bytes

Write-Host "Created: $($resp.url)"
Write-Output $resp.url

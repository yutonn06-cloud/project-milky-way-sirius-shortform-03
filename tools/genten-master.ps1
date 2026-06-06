# 原典マスター DB — import + usage sync (Notion REST, local-only / needs .env NOTION_TOKEN).
#
# A案 (2026-06-06): 原文集450本のマスター台帳を Notion に持ち、原文番号で
# Rewrite Script DB と突合して「使用回数 / 最新ステータス / 最終使用日」をスタンプする。
# これにより「どのテーマが枯れ、どこが手つかず（未使用原典＝次ネタ候補）か」を可視化する。
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\genten-master.ps1 -Import   # CSV→DB (idempotent: 既存原文番号はスキップ)
#   powershell -ExecutionPolicy Bypass -File tools\genten-master.ps1 -Sync     # Rewrite Script 突合→スタンプ
#   powershell -ExecutionPolicy Bypass -File tools\genten-master.ps1 -Import -Sync
#
# 結合キー: 原文番号 (master=NUMBER 1-450) ⇔ Rewrite Script "原文NNN" (text)。両側を整数へ正規化して突合。
# REST直叩き (MCP不使用) — pattern mirrors tools/notion-create-page.ps1。クラウドでは .env 不在のため動かない (ローカル専用)。

[CmdletBinding()]
param(
    [switch]$Import,
    [switch]$Sync
)

$ErrorActionPreference = "Stop"

if (-not $Import -and -not $Sync) {
    Write-Host "Nothing to do. Pass -Import and/or -Sync."
    exit 0
}

# ---- env ----
$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile  = Join-Path $repoRoot ".env"
if (-not (Test-Path $envFile)) { Write-Error "Missing .env at $envFile"; exit 1 }
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item "Env:$($Matches[1])" $Matches[2] }
}
if (-not $env:NOTION_TOKEN) { Write-Error "NOTION_TOKEN missing from .env"; exit 1 }

$MASTER_DB = "b363842b-500a-4ad8-9914-17fd89225193"   # 原典マスター
$REWRITE_DB = "087eff43-caa5-41ff-944e-7982f68faef8"  # Rewrite Script (突合元)
$CSV = Join-Path $repoRoot "docs\原典マスター.csv"

$headers = @{
    "Authorization"  = "Bearer $env:NOTION_TOKEN"
    "Notion-Version" = "2022-06-28"
    "Content-Type"   = "application/json; charset=utf-8"
}

# Invoke-RestMethod with UTF-8 body + 429 retry/backoff (Notion ~3 req/s).
function Invoke-Notion {
    param([string]$Method, [string]$Uri, $Body)
    $bytes = $null
    if ($null -ne $Body) {
        $json  = $Body | ConvertTo-Json -Depth 20 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            if ($null -ne $bytes) {
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $bytes
            }
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if (($code -eq 429 -or $code -ge 500) -and $attempt -lt 5) {
                Start-Sleep -Milliseconds (400 * $attempt)
                continue
            }
            throw
        }
    }
}

# Query all pages of a database (handles pagination).
function Get-AllPages {
    param([string]$DbId)
    $all = @()
    $cursor = $null
    do {
        $body = @{ page_size = 100 }
        if ($cursor) { $body.start_cursor = $cursor }
        $resp = Invoke-Notion -Method Post -Uri "https://api.notion.com/v1/databases/$DbId/query" -Body $body
        $all += $resp.results
        $cursor = $resp.next_cursor
    } while ($resp.has_more)
    return $all
}

# Pull just the digits out of "原文019" / "019" / 19 → [int]19 (null if none).
function ConvertTo-GentenNum {
    param($Raw)
    if ($null -eq $Raw) { return $null }
    $m = [regex]::Match("$Raw", '\d+')
    if ($m.Success) { return [int]$m.Value }
    return $null
}

# =====================================================================
# IMPORT — CSV(450) → master DB. Idempotent: skips 原文番号 already present.
# =====================================================================
if ($Import) {
    Write-Host "[import] reading $CSV ..."
    $rows = Import-Csv -Path $CSV
    Write-Host "[import] CSV rows: $($rows.Count)"

    Write-Host "[import] fetching existing master pages ..."
    $existing = @{}
    foreach ($pg in (Get-AllPages -DbId $MASTER_DB)) {
        $n = $pg.properties.'原文番号'.number
        if ($null -ne $n) { $existing[[int]$n] = $true }
    }
    Write-Host "[import] already present: $($existing.Count)"

    $created = 0; $skipped = 0
    foreach ($r in $rows) {
        $num = [int]$r.num
        if ($existing.ContainsKey($num)) { $skipped++; continue }
        $props = @{
            "タイトル"   = @{ title     = @(@{ text = @{ content = "$($r.title)" } }) }
            "原文番号"   = @{ number    = $num }
            "カテゴリ"   = @{ select    = @{ name = "$($r.category)" } }
            "テーマ"     = @{ select    = @{ name = "$($r.theme)" } }
            "sourcefile" = @{ rich_text = @(@{ text = @{ content = "$($r.sourcefile)" } }) }
            "使用回数"   = @{ number    = 0 }
        }
        $payload = @{ parent = @{ database_id = $MASTER_DB }; properties = $props }
        Invoke-Notion -Method Post -Uri "https://api.notion.com/v1/pages" -Body $payload | Out-Null
        $created++
        if ($created % 25 -eq 0) { Write-Host "[import] created $created ..." }
        Start-Sleep -Milliseconds 120
    }
    Write-Host "[import] done. created=$created skipped(existing)=$skipped"
}

# =====================================================================
# SYNC — aggregate Rewrite Script usage per 原文番号 → stamp master DB.
#   使用回数      = count of Rewrite Script records for that 原文番号
#   最新ステータス = ステータス of the most-recently-created record
#   最終使用日    = created date of the most-recent record
# Genten with zero usage are reset to 使用回数=0 / 最新ステータス未使用 / 最終使用日クリア.
# =====================================================================
if ($Sync) {
    Write-Host "[sync] fetching Rewrite Script records ..."
    $rewrites = Get-AllPages -DbId $REWRITE_DB
    Write-Host "[sync] Rewrite Script records: $($rewrites.Count)"

    # Aggregate by normalized 原文番号.
    $agg = @{}  # num -> @{ count; latest(DateTime); status }
    foreach ($pg in $rewrites) {
        $rawProp = $pg.properties.'原文番号'
        $raw = ($rawProp.rich_text | ForEach-Object { $_.plain_text }) -join ''
        $num = ConvertTo-GentenNum $raw
        if ($null -eq $num) { continue }
        $created = [datetime]$pg.created_time
        $status  = $pg.properties.'ステータス'.select.name
        if (-not $agg.ContainsKey($num)) {
            $agg[$num] = @{ count = 0; latest = $created; status = $status }
        }
        $agg[$num].count++
        if ($created -ge $agg[$num].latest) {
            $agg[$num].latest = $created
            $agg[$num].status = $status
        }
    }
    Write-Host "[sync] distinct 原文番号 used: $($agg.Count)"

    Write-Host "[sync] fetching master pages ..."
    $masters = Get-AllPages -DbId $MASTER_DB
    Write-Host "[sync] master pages: $($masters.Count)"

    $updated = 0; $unchanged = 0
    foreach ($pg in $masters) {
        $num = $pg.properties.'原文番号'.number
        if ($null -eq $num) { continue }
        $num = [int]$num

        $curCount  = $pg.properties.'使用回数'.number
        $curStatus = $pg.properties.'最新ステータス'.select.name
        $curDate   = $pg.properties.'最終使用日'.date.start

        if ($agg.ContainsKey($num)) {
            $newCount  = $agg[$num].count
            $newStatus = $agg[$num].status
            $newDate   = $agg[$num].latest.ToString('yyyy-MM-dd')
        } else {
            $newCount  = 0
            $newStatus = "未使用"
            $newDate   = $null
        }

        $curDateNorm = if ($curDate) { ([datetime]$curDate).ToString('yyyy-MM-dd') } else { $null }
        $curCountNorm = if ($null -ne $curCount) { [int]$curCount } else { 0 }
        if (($curCountNorm -eq $newCount) -and ($curStatus -eq $newStatus) -and ($curDateNorm -eq $newDate)) {
            $unchanged++
            continue
        }

        $props = @{
            "使用回数"     = @{ number = $newCount }
            "最新ステータス" = @{ select = @{ name = $newStatus } }
        }
        if ($newDate) {
            $props."最終使用日" = @{ date = @{ start = $newDate } }
        } else {
            $props."最終使用日" = @{ date = $null }
        }
        $payload = @{ properties = $props }
        Invoke-Notion -Method Patch -Uri "https://api.notion.com/v1/pages/$($pg.id)" -Body $payload | Out-Null
        $updated++
        Start-Sleep -Milliseconds 120
    }
    Write-Host "[sync] done. updated=$updated unchanged=$unchanged"
}

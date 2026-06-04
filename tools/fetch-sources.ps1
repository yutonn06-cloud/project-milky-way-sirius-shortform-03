# Authentic-source fetcher -- pulls top items from 4 active RSS feeds for citation in SNS posts.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\fetch-sources.ps1
#       Refreshes .tmp/sources_today.json if older than 6 hours (or missing).
#
#   powershell -ExecutionPolicy Bypass -File tools\fetch-sources.ps1 -Force
#       Refresh regardless of cache age.
#
# Output: .tmp/sources_today.json -- array of {source, title, url, pubDate, summary}
#         Top 3 items per feed (12 total when all 4 feeds healthy).
#
# Note: FutureTimeline.net does not expose a real RSS feed -- it serves a directory listing
# at every common path we probed. It remains as a "long-term context reference" the agent
# can name without fetching (see reference/authentic-sources.md).
#
# Consumed by: .claude/skills/sns-rewrite/SKILL.md §4.5, .claude/skills/sns-rewrite-x/SKILL.md §4.5
# Workflow:    workflows/cite_authentic_source.md

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$tmpDir   = Join-Path $repoRoot ".tmp"
$outFile  = Join-Path $tmpDir "sources_today.json"

if (-not (Test-Path $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
}

if ((Test-Path $outFile) -and -not $Force) {
    $age = (Get-Date) - (Get-Item $outFile).LastWriteTime
    if ($age.TotalHours -lt 6) {
        Write-Host ("Cache fresh ({0:N1}h old): {1}" -f $age.TotalHours, $outFile)
        exit 0
    }
}

$feeds = @(
    @{ source = "内閣府";              url = "https://www.cao.go.jp/rss/news.rdf" }
    @{ source = "厚生労働省";          url = "https://www.mhlw.go.jp/stf/news.rdf" }
    @{ source = "Yahoo!ニュース（国内）"; url = "https://news.yahoo.co.jp/rss/categories/domestic.xml" }
    @{ source = "NHKニュース";         url = "https://www.nhk.or.jp/rss/news/cat1.xml" }
)

function ConvertTo-PlainText {
    param([string]$Html)
    if (-not $Html) { return "" }
    $text = $Html -replace '<[^>]+>', ''
    $text = $text -replace '&lt;', '<' -replace '&gt;', '>' -replace '&amp;', '&' -replace '&quot;', '"' -replace '&#\d+;', ''
    return ($text -replace '\s+', ' ').Trim()
}

function Get-XmlText {
    param($Node)
    if ($null -eq $Node) { return "" }
    if ($Node -is [string]) { return $Node }
    if ($Node -is [System.Xml.XmlElement]) { return $Node.InnerText }
    if ($Node.PSObject.Properties.Name -contains '#text') { return $Node.'#text' }
    if ($Node.href) { return "$($Node.href)" }
    return "$Node"
}

# Use WebClient with UTF-8 to avoid the Latin-1 default that mojibakes Japanese feeds (NHK).
$client = New-Object System.Net.WebClient
$client.Encoding = [System.Text.Encoding]::UTF8
$client.Headers.Add("User-Agent", "rewrite-agent/1.0 (+https://github.com/yutonn06-cloud)")

$results = @()

foreach ($feed in $feeds) {
    try {
        Write-Host "Fetching: $($feed.source) -- $($feed.url)"
        $content = $client.DownloadString($feed.url)
        [xml]$xml = $content

        $items = $null
        if ($xml.rss -and $xml.rss.channel -and $xml.rss.channel.item) {
            $items = @($xml.rss.channel.item)
        } elseif ($xml.feed -and $xml.feed.entry) {
            $items = @($xml.feed.entry)
        } elseif ($xml.RDF -and $xml.RDF.item) {
            $items = @($xml.RDF.item)
        }

        if (-not $items -or $items.Count -eq 0) {
            Write-Warning "$($feed.source): no items parsed"
            continue
        }

        $top = $items | Select-Object -First 3
        foreach ($it in $top) {
            $title = Get-XmlText $it.title
            $link  = Get-XmlText $it.link
            $date  = if ($it.pubDate) { Get-XmlText $it.pubDate } elseif ($it.updated) { Get-XmlText $it.updated } elseif ($it.date) { Get-XmlText $it.date } else { "" }
            $desc  = if ($it.description) { Get-XmlText $it.description } elseif ($it.summary) { Get-XmlText $it.summary } else { "" }

            $results += [pscustomobject]@{
                source  = $feed.source
                title   = (ConvertTo-PlainText $title)
                url     = $link.Trim()
                pubDate = $date.Trim()
                summary = (ConvertTo-PlainText $desc)
            }
        }
    } catch {
        Write-Warning "$($feed.source): $($_.Exception.Message)"
    }
}

if ($results.Count -eq 0) {
    Write-Error "All feeds failed -- nothing written"
    exit 2
}

$results | ConvertTo-Json -Depth 4 | Set-Content -Path $outFile -Encoding UTF8
Write-Host ("Wrote {0} items to {1}" -f $results.Count, $outFile)

# SNS Rewrite Automation

Daily-scheduled cloud agent that generates A/B SNS rewrite content and writes to Notion. Audio (ElevenLabs TTS) is filled in locally afterwards because the cloud sandbox blocks `api.elevenlabs.io`.

## Architecture

```
                  ┌─────────────────────────────────┐
   06:00 JST cron │   Cloud routine (claude.ai)     │
   ───────────►   │   - read .claude/skills/        │
                  │     sns-rewrite/SKILL.md        │
                  │   - fetch 4 RSS (出典候補)       │
                  │   - pick random 原文            │
                  │   - rewrite A/B + 出典 line     │
                  │   - POST Notion via REST        │
                  └────────────┬────────────────────┘
                               │ Notion entry created
                               ▼
                  ┌─────────────────────────────────┐
   manual or      │   Local: tools/audio-filler.ps1 │
   Task Scheduler │   - poll Notion for empty audio │
   ───────────►   │   - generate A/B via ElevenLabs │
                  │   - patch Notion with localhost │
                  │     URLs                        │
                  └────────────┬────────────────────┘
                               │ URLs in Notion
                               ▼
                  ┌─────────────────────────────────┐
   user clicks    │   Local: tools/audio-proxy.ps1  │
   URL in Notion  │   adds xi-api-key, streams mp3  │
   ───────────►   │   from ElevenLabs history       │
                  └─────────────────────────────────┘
```

## Repo layout

```
.
├── .env                       # local creds (gitignored — never committed)
├── trigger-prompt.md          # short-video routine prompt (cron 06:00 JST)
├── trigger-prompt-x.md        # X long-form routine prompt (manual)
├── .claude/
│   └── skills/                # canonical Claude Code skill location
│       ├── README.md          # orchestrator + Notion DB schema
│       ├── sns-rewrite/
│       │   └── SKILL.md       # short-video skill
│       └── sns-rewrite-x/
│           └── SKILL.md       # X long-form skill
├── workflows/
│   └── cite_authentic_source.md   # citation SOP (4 RSS feeds)
├── reference/
│   └── authentic-sources.md   # source registry (RSS + static refs)
├── skill/
│   └── references/            # 45 files, 450 原文 (input pool)
├── tools/
│   ├── audio-proxy.ps1        # localhost:8765 → ElevenLabs streaming proxy
│   ├── audio-filler.ps1       # poll Notion + fill audio URLs
│   ├── audio-filler.sh        # GitHub Actions counterpart
│   ├── fetch-sources.ps1      # cache 12 RSS items → .tmp/sources_today.json
│   └── notion-create-page.ps1 # REST POST to Notion (replaces MCP create-pages)
└── README.md
```

**MCP は不要（REST 直叩き）：** Notion 操作は `tools/notion-create-page.ps1`（ローカル）または直接 `https://api.notion.com/v1/pages` への POST（クラウド）で行う。MCP サーバを有効化していると20以上のツールスロットを消費するため、本リポジトリでは使わない方針。

## One-time setup

### 1. Local `.env`

Create `.env` in the repo root:

```
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_VOICE_ID=...
NOTION_TOKEN=secret_...
NOTION_DATABASE_ID=<32-hex>
```

### 2. Notion integration token (for `audio-filler.ps1`)

The local script needs Notion API access (separate from the claude.ai MCP connector used by the cloud routine).

1. Go to https://www.notion.so/my-integrations → **+ New integration** → name it (e.g. "SNS Audio Filler"), workspace = your workspace, type = Internal
2. Copy the **Internal Integration Token** → paste into `.env` as `NOTION_TOKEN`
3. Open the Notion DB **Rewrite Script** (under page **Rewrite for Short Video**)
4. Click **⋯** (top-right) → **Connections** → **Add connections** → select the integration you just created
5. Find the database_id from the URL and paste into `.env` as `NOTION_DATABASE_ID`. URL format:
   `https://www.notion.so/<workspace>/<DB_NAME>-<32-hex>?v=...`
   The 32-hex chunk after the last dash (before `?v=`) is the database_id.

### 3. Cloud routine

The routine `trig_0146gAGPHZ44FndRHDcuKBjm` (`SNS Rewrite Daily`) is already configured. It points at this repo on GitHub. Credentials live in the routine prompt body (private to your claude.ai account); they are NOT committed to git.

If you ever recreate it, the canonical prompt is in `trigger-prompt.md`. Register via `RemoteTrigger` API; do NOT use the routine's pencil/edit UI (it strips MCP tool allow-lists).

## Daily flow

1. **06:00 JST** — cloud routine fires automatically. Writes a Notion page with A/B rewrite text. Audio URL fields stay empty.
2. **You run the audio filler** locally — manual, or schedule via Task Scheduler:
   ```
   powershell -ExecutionPolicy Bypass -File tools\audio-filler.ps1
   ```
   It queries Notion for entries with empty 音声URL_A, generates A+B audio via ElevenLabs, patches the page with `http://localhost:8765/audio/{id}` URLs.
3. **Audio proxy must be running** for the URLs to play — see below.

To process a single page (e.g. immediately after running the cloud routine):
```
powershell -ExecutionPolicy Bypass -File tools\audio-filler.ps1 -PageId 351f7051886d815c9c87d7c03efc59d2
```

## Reviewing in Notion

The Notion DB `Rewrite Script` (parent: `Rewrite for Short Video`) collects rows from every platform sub-skill — short-video, X, and any future platform — distinguished by the `投稿先` (platform) column.

1. Open the DB in **Table view** — `リライト本文` (A案) and `リライト本文B` (B案) are visible side-by-side.
2. Click any cell in either body column to copy the text.
3. Set the `採用` field: `A案` / `B案` / `両方` / `不採用` / `未判定` (default).
4. After publishing, set `ステータス` to `使用済み`.

**Pre-built views** (already created in the DB — switch tabs at the top of the database):

| View name | Purpose | Filter |
|---|---|---|
| `X — Pending Review` | X long-form awaiting review | `投稿先 = X AND 採用 = 未判定` |
| `Short Video — Pending Review` | Short-video awaiting review (includes audio URLs) | `投稿先 = ショート動画 AND 採用 = 未判定` |
| `Approved (Post Candidates)` | Anything marked as A案 / B案 / 両方 | `採用 IN (A案, B案, 両方)` |
| `Published (Archive)` | Posts that have shipped | `ステータス = 使用済み` |
| `Board by Platform` | Kanban grouped by platform | `GROUP BY 投稿先` |

**Note:** The filter expressions still reference the underlying property/value names (`投稿先`, `採用`, `ショート動画`, `未判定`, etc.) because those are the live Notion DB schema and are also used in REST API calls — renaming them would break the code. Only the view *labels* and the DB title are user-facing strings, safe to change.

**Manual UI rename steps** (do these once in Notion to match this README):
1. DB title: rename `リライトスクリプト` → `Rewrite Script`.
2. Each of the 5 views: click the view tab → ⋯ → Rename, using the names in the table above.
3. No code changes needed — the DB is referenced by ID (`087eff43-caa5-41ff-944e-7982f68faef8`), and views are never queried by name.

For the full DB schema (all property types and values), see [.claude/skills/README.md](.claude/skills/README.md) → `Notion DB property reference`.

## Audio proxy (required for Notion audio links to play)

The `音声URL_A` / `音声URL_B` fields contain `http://localhost:8765/audio/{id}` URLs. These require the proxy script to be running.

**Manual start (each session):**
```
powershell -ExecutionPolicy Bypass -File tools\audio-proxy.ps1
```
Leave that window open while you review content in Notion. Click any audio URL in Notion → audio streams + plays in browser.

**Auto-start at login (recommended):**
1. Task Scheduler → Create Task
2. General: name = "ElevenLabs Audio Proxy", "Run only when user is logged on"
3. Triggers: New → At log on
4. Actions: New → Program `powershell.exe`, Arguments `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\yuton\OneDrive\Desktop\Claude_Rewrite_Agent\tools\audio-proxy.ps1"`
5. Save → run once to confirm

**Stop:**
```
Get-NetTCPConnection -LocalPort 8765 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

## Auto-fill on a schedule (optional)

To run `audio-filler.ps1` automatically ~30 min after the cloud routine fires (so the Notion page exists by then):

1. Task Scheduler → Create Task
2. Triggers: Daily at **06:30 JST**
3. Actions: `powershell.exe`, Arguments `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\yuton\OneDrive\Desktop\Claude_Rewrite_Agent\tools\audio-filler.ps1"`
4. Conditions: only if PC is awake (otherwise the run is skipped that day, but no permanent state is lost — next morning's run picks it up)

The filler is idempotent — entries that already have audio URLs are skipped.

## Security

- `.env` is gitignored — never committed. Contains the live ElevenLabs key and Notion integration token.
- Repo is **public** on GitHub (`github.com/yutonn06-cloud/sns-rewrite-automation`). Cloud routine clones it. No secrets are in the repo or git history.
- ElevenLabs credentials for the cloud routine live in the routine prompt body, which is private to your claude.ai account.
- If you ever rotate the ElevenLabs key: update `.env` AND update the routine prompt via `RemoteTrigger update`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Routine "Failed to start run" | `NOTION_TOKEN` missing/expired in routine env or .env | Refresh integration token at notion.so/my-integrations; update routine prompt and `.env` |
| Cloud run completes, no Notion entry | REST POST to api.notion.com failed (auth header / 投稿先 select option missing / DB id wrong) | Inspect routine logs; verify `Authorization: Bearer ${NOTION_TOKEN}` header and that all `select` option names exist in the DB |
| `audio-filler.ps1` returns 0 entries | All entries already have audio, OR filter property name mismatch | Open Notion, confirm a 音声URL_A is empty; check `NOTION_DATABASE_ID` in .env |
| `audio-filler.ps1` 401 from Notion | Integration not added as a connection on the DB | DB page → ⋯ → Connections → add the integration |
| `audio-filler.ps1` 401 from ElevenLabs | Wrong API key in .env, or scope missing | Verify key at elevenlabs.io/app/settings/api-keys; needs `text_to_speech` scope |
| URL in Notion returns 502 | Audio proxy not running | Start `tools/audio-proxy.ps1` |
| URL in Notion returns 401 | API key in `.env` lacks `speech_history_read` scope | Edit key on ElevenLabs settings → enable scope |

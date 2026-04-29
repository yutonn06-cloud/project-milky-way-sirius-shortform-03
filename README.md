# SNS Rewrite Automation

Daily-scheduled cloud agent that generates A/B SNS rewrite content and writes to Notion. Audio (ElevenLabs TTS) is filled in locally afterwards because the cloud sandbox blocks `api.elevenlabs.io`.

## Architecture

```
                  ┌─────────────────────────────────┐
   06:00 JST cron │   Cloud routine (claude.ai)     │
   ───────────►   │   - read skill/SKILL.md         │
                  │   - pick random source          │
                  │   - rewrite A/B                 │
                  │   - write Notion page (no audio)│
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
├── .env                  # local creds (gitignored — never committed)
├── trigger-prompt.md     # canonical copy of the routine prompt (sync via RemoteTrigger)
├── tools/
│   ├── audio-proxy.ps1   # localhost:8765 → ElevenLabs streaming proxy
│   └── audio-filler.ps1  # poll Notion + fill audio URLs
├── skill/
│   ├── SKILL.md
│   └── references/       # 45 files, 450 originals
└── README.md
```

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
3. Open the Notion DB「リライトスクリプト」 (under page「Rewrite for Short Video」)
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
| Routine "Failed to start run" | Notion MCP OAuth expired on claude.ai | Settings → Connectors → Notion → Reconnect; then re-add to routine |
| Cloud run completes, no Notion entry | Notion MCP not in routine's `permitted_tools` | Re-apply via `RemoteTrigger update` (don't use UI pencil) |
| `audio-filler.ps1` returns 0 entries | All entries already have audio, OR filter property name mismatch | Open Notion, confirm a 音声URL_A is empty; check `NOTION_DATABASE_ID` in .env |
| `audio-filler.ps1` 401 from Notion | Integration not added as a connection on the DB | DB page → ⋯ → Connections → add the integration |
| `audio-filler.ps1` 401 from ElevenLabs | Wrong API key in .env, or scope missing | Verify key at elevenlabs.io/app/settings/api-keys; needs `text_to_speech` scope |
| URL in Notion returns 502 | Audio proxy not running | Start `tools/audio-proxy.ps1` |
| URL in Notion returns 401 | API key in `.env` lacks `speech_history_read` scope | Edit key on ElevenLabs settings → enable scope |

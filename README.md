# SNS Rewrite Automation

Daily-scheduled cloud agent that uses `sns-rewrite-skill` to generate A/B SNS rewrite content + TTS audio, writes to Notion, uploads audio to Google Drive.

## Repo layout

```
.
├── .env                # ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID (committed — keep repo PRIVATE)
├── trigger-prompt.md   # Prompt registered with the daily routine
├── skill/              # The sns-rewrite skill the agent loads at runtime
│   ├── SKILL.md
│   └── references/     # 45 files, 450 originals
└── README.md
```

## Setup (one-time)

1. **Fill `.env`** — paste your ElevenLabs API key and voice_id.
2. **Create a PRIVATE GitHub repo** (e.g., `yutonn06/sns-rewrite-automation`).
3. **Push** this folder.
4. **Give the repo URL to Claude** so the daily routine can be created pointing at it.

## Schedule

- Cron: `0 21 * * *` UTC = **06:00 Asia/Tokyo daily**
- Model: claude-sonnet-4-6
- Connectors: Notion (Drive removed — see audio handling below)

## Audio proxy (must be running on this PC for Notion audio links to play)

The Notion `音声URL_A` / `音声URL_B` fields contain `http://localhost:8765/audio/{id}` URLs. They require the proxy script to be running.

**Manual start (each session):**
```
powershell -ExecutionPolicy Bypass -File tools\audio-proxy.ps1
```
Leave that window open while you review content in Notion. Click any audio URL in Notion → audio streams + plays in browser.

**Auto-start at login (recommended):**
1. Open Task Scheduler → Create Task...
2. General tab: Name = "ElevenLabs Audio Proxy", check "Run only when user is logged on"
3. Triggers tab: New → "At log on"
4. Actions tab: New → Program: `powershell.exe`, Arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\yuton\OneDrive\Desktop\Claude_Rewrite_Agent\tools\audio-proxy.ps1"`
5. Conditions tab: uncheck "Start the task only if the computer is on AC power" if you want it on battery too
6. Save → run once to confirm

**Stop:**
```
Get-NetTCPConnection -LocalPort 8765 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

## Security note

`.env` is intentionally **not** in `.gitignore` — the cloud routine clones this repo and reads the key from `.env`. **The repo MUST stay private.** If you ever flip it public, rotate the ElevenLabs key immediately.

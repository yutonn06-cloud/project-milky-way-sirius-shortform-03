# SNS Short-Video Script Rewriter — Claude Code Instructions

## Overview

This system automatically generates rewritten scripts for short-form video content (Instagram Reels, YouTube Shorts, Threads, X, etc.) from a library of 450 Japanese source texts. It produces **two variants (Plan A and Plan B)** per run, saves results to a Notion database, and generates voice audio via the ElevenLabs API.

**Language:** All source texts and output are in **Japanese**. Instructions are in English for Claude Code compatibility.

**Operational source of truth:** This file is a design reference. The runtime workflow the cloud routine executes is `skill/SKILL.md` (loaded at runtime) plus the autonomous-mode overrides in `trigger-prompt.md` (registered with the `/schedule` routine).

---

## Architecture

```
Source Texts (450 articles)
    ↓ Random selection
Rewrite Engine (2 variants: A & B)
    ↓
Notion Database (structured record with both variants)
    ↓
ElevenLabs TTS API (optional voice generation)
```

---

## Source Text Library

### Location

Source texts are stored in `skill/references/` relative to the repo root.

### Structure

| Set | Prefix | Content | Articles | Range |
|-----|--------|---------|----------|-------|
| 1 | `ch01`–`ch10` | Philosophy series (10 chapters) | 100 | 001–100 |
| 2 | `s01`–`s15` | Spiritual series (15 series) | 150 | 101–250 |
| 3 | `t01`–`t10` | Society & awakening (10 themes) | 100 | 251–350 |
| 4 | `v01`–`v10` | Society & awakening Vol.2 (10 themes) | 100 | 351–450 |

### File Format

Each file contains 10 source texts separated by `===`, with headers in the format `## 原文XXX：Title`.

### Index

`skill/references/index.md` contains the full inventory of all files and article counts.

---

## Workflow

### Step 1: Select Source Text

**Priority order:**
1. If the user provides a source text directly → use it as-is
2. If a specific article number is requested (e.g., "原文003") → load the corresponding file and extract that article
3. Otherwise → randomly select one:
   - Pick a random file from all 45 reference files
   - Pick a random article from the 10 within that file
   - Avoid repeating the most recently used article

**Report the selection** to the user before proceeding: article number + title.

### Step 2: Select Parameters

If the user has already specified parameters, use them. Otherwise, **randomly select** one option from each of the three axes below. When running interactively, present 2–3 options per axis for the user to choose from. When running as an automated scheduled task, select all parameters randomly without user input.

#### Axis A: Target Audience

| # | Target Audience (Japanese) |
|---|---------------------------|
| 1 | 40代〜50代で、生き方に違和感を感じ始めた女性 |
| 2 | 「自分の人生これでいいのか」と思い始めた30代〜40代の会社員 |
| 3 | 周りに合わせて生きてきたけど、もう限界を感じている人 |
| 4 | スピリチュアルに興味はあるけど、周りには言えずにいる女性 |
| 5 | 子育てがひと段落して「自分の人生」を取り戻したいと感じている主婦 |
| 6 | 職場の人間関係に疲れて、ひとりで働く生き方に憧れている人 |
| 7 | 「自分は普通じゃない」と感じて、ずっと孤独を抱えてきた人 |
| 8 | 離婚・退職・病気など、人生の転機を経験して価値観が変わった人 |
| 9 | SNSで自己啓発やスピリチュアルの発信を見て、自分も変わりたいと思い始めた人 |
| 10 | 組織に属さず、自分の力で生きていきたいと考えている40代〜50代 |

#### Axis B: Writing Style / Tone

| # | Style (Japanese) | Best For |
|---|-----------------|----------|
| 1 | やさしく語りかけるけど、核心はズバッと言い切るトーン | Spiritual content, warmth + impact |
| 2 | 友達に話すようなカジュアルな口調。軽すぎず信頼感あり | Threads, Instagram — approachable |
| 3 | 静かだけど力強い、ひとり語りのようなトーン | YouTube scripts, blogs — contemplative |
| 4 | です・ます調ベースに、体言止めや問いかけを混ぜてリズムを出す | X, Threads long posts — rhythmic |
| 5 | 読者の痛みにまず共感してから、視点を反転させる構成 | Persuasive content — empathy → twist |

#### Axis C: Platform / Purpose

| # | Platform | Character Count |
|---|----------|----------------|
| 1 | Threads | 350–500 chars |
| 2 | X (Twitter) | 125–130 chars |
| 3 | Blog article | 600–700 chars |
| 4 | YouTube script | 400–600 chars |
| 5 | Instagram Reels captions | 10–15 chars per line |
| 6 | Short video script | 300–400 chars |

### Step 3: Generate Two Variants (Plan A & Plan B)

**Always produce exactly two variants** from the same source text.

#### Differentiation Rules

- Plan A and Plan B use the **same source text, same target audience, and same platform**
- They **differ in writing style, tone, opening hook, structure, and closing**
- Example: Plan A = gentle, question-led opening / Plan B = bold, declarative opening
- Example: Plan A = empathy-first structure / Plan B = twist-reveal structure
- Each variant must feel distinctly different — not just minor word changes

#### Core Rewriting Rules

- Use polite Japanese (です・ます調) by default unless style dictates otherwise
- **Strictly adhere** to the character count range for the selected platform
- Preserve the core message of the source text while adapting word choice for the target audience
- Cut redundancy; keep sentences short
- Do not merely shorten the original — **rewrite** it for the selected audience and tone

#### Platform-Specific Guidelines

**Threads:**
- Open with a question or bold statement that makes the reader think "this is about me"
- Close with lingering emotion — empathy or hope
- Use generous line breaks for visual readability

**X (Twitter):**
- Strip all excess — maximum density
- Complete in 125–130 characters including line breaks
- Lead with a high-impact single sentence

**Blog:**
- Create a hook at the end of each paragraph to pull the reader forward
- No headings (body text only)
- Weave in concrete examples the reader can relate to

**YouTube Script:**
- Convert written language to spoken language (use 〜なんですよね, 〜じゃないですか)
- Insert line breaks for pacing (間/ma)
- Create a rhythm the listener can nod along to

**Instagram Reels Captions:**
- Keep each line to 10–15 characters
- Maintain tempo with short, punchy phrases
- Optimize for on-screen readability

**Short Video Script:**
- Hook in the first 3 seconds with a compelling opening line
- Total length must be readable within 60 seconds
- Build emotional arc into the structure

### Step 4: Output Format

Display the results in this format:

```
【原文】原文XXX：{title}
【ターゲット】{selected target audience}
【投稿先】{selected platform}

━━ A案 ━━
【文体】{Plan A style description}
【文字数】{Plan A character count}文字

{Plan A rewritten text}

━━ B案 ━━
【文体】{Plan B style description}
【文字数】{Plan B character count}文字

{Plan B rewritten text}
```

### Step 5: Save to Notion

Write the results to the Notion database automatically after generation.

#### Database Details

- **Database name:** リライトスクリプト
- **Parent page:** "Rewrite for Short Video"
- **Data source ID:** `e8322351-3390-420a-af36-19d6836bee0c`

#### Property Mapping

| Notion Property | Value |
|----------------|-------|
| タイトル | Source text title (e.g., "週末が怖い") |
| リライト本文 | Plan A full text (copyable snippet) |
| リライト本文B | Plan B full text (copyable snippet) |
| 投稿先 | One of: Threads / X / ブログ / YouTube台本 / Reels / ショート動画 |
| ターゲット | Selected target audience description |
| 文体 | Both styles (e.g., "A: やさしく語りかける / B: 共感→反転の構成") |
| 原文番号 | Article ID (e.g., "原文001") |
| 文字数 | Plan A character count (number) |
| 文字数B | Plan B character count (string) |
| 採用 | "未判定" (default — user reviews later) |
| ステータス | "未使用" (default) |
| 音声URL_A | ElevenLabs audio URL for Plan A (populated in Step 6) |
| 音声URL_B | ElevenLabs audio URL for Plan B (populated in Step 6) |
| メモ | Empty (user fills in later) |

#### Notion API Call Example

```json
{
  "parent": {
    "data_source_id": "e8322351-3390-420a-af36-19d6836bee0c",
    "type": "data_source_id"
  },
  "pages": [{
    "properties": {
      "タイトル": "週末が怖い",
      "リライト本文": "(Plan A text)",
      "リライト本文B": "(Plan B text)",
      "投稿先": "Threads",
      "ターゲット": "40代〜50代で、生き方に違和感を感じ始めた女性",
      "文体": "A: やさしく語りかける / B: 共感→反転の構成",
      "原文番号": "原文001",
      "文字数": 420,
      "文字数B": "385",
      "採用": "未判定",
      "ステータス": "未使用"
    }
  }]
}
```

**Important:** Write to Notion automatically without asking for user confirmation. Report "Notionに保存しました" after successful write.

### Step 6: Generate Voice Audio (ElevenLabs) → Capture history URL → Write to Notion

Generate TTS audio for both Plan A and Plan B and persist the ElevenLabs history URL.

#### Credentials

The repo is **public**. Credentials are NOT stored in the repo. They are embedded inline in the cloud routine's prompt body (which is private to the user's claude.ai account) and injected as shell environment variables before the API call:

```
export ELEVENLABS_API_KEY="<from-routine-prompt>"
export ELEVENLABS_VOICE_ID="<from-routine-prompt>"
```

For local manual runs, `.env` at the repo root provides the same variables (gitignored, never committed). The local audio proxy (`tools/audio-proxy.ps1`) reads from this local `.env`.

In autonomous (cloud routine) mode the agent **must not** prompt for credentials — if they're missing from the prompt body, write a "失敗" record to Notion and exit.

#### API Call (capture history-item-id from response headers)

For each plan (A and B), execute:

```bash
curl -sS -D headers.txt -X POST \
  "https://api.elevenlabs.io/v1/text-to-speech/${ELEVENLABS_VOICE_ID}?output_format=mp3_22050_32" \
  -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
  -H "Content-Type: application/json" \
  --data-binary @payload.json \
  --output /tmp/audio.mp3
HID=$(grep -i 'history-item-id' headers.txt | awk '{print $2}' | tr -d '\r\n')
URL="https://api.elevenlabs.io/v1/history/${HID}/audio"
```

The `history-item-id` response header is exposed via `access-control-expose-headers` and is always present on a 200 OK from text-to-speech.

#### Post-Processing

1. Generate audio at `output_format=mp3_22050_32` (smallest available; works with the routine's tool size limits)
2. Capture `history-item-id` from response headers — no extra API call needed
3. Construct the **localhost proxy URL** `http://localhost:8765/audio/{id}` (NOT the raw ElevenLabs API URL)
4. Write into Notion: A URL → `音声URL_A`, B URL → `音声URL_B`
5. The local mp3 file is the source of truth for that one run; it does not need to be persisted (the URL plus the running proxy reproduces it)

#### Why localhost proxy

The raw ElevenLabs URL `https://api.elevenlabs.io/v1/history/{id}/audio` requires the `xi-api-key` header — browsers don't send it on a plain link click, so the URL is not directly clickable from Notion. The local proxy at `tools/audio-proxy.ps1` listens on `localhost:8765`, reads the API key from `.env`, and forwards browser requests with the auth header attached. Click in Notion → proxy adds key → audio streams + plays inline.

The user must have `tools/audio-proxy.ps1` running (manually or via Task Scheduler at startup) for the URLs to play. See README.md → "Audio proxy" for setup.

#### URL playback prerequisites

- API key must have `speech_history_read` permission (one-time setup at https://elevenlabs.io/app/settings/api-keys)
- The `tools/audio-proxy.ps1` script must be running on the user's machine

#### Why not Google Drive

Drive MCP `create_file` requires the full audio as a single base64-encoded string in a tool-call parameter. For 30-second mp3s (~250KB), the resulting base64 (~350KB) exceeds Read/tool token limits in both the Claude Code VSCode session and the cloud routine sandbox, making Drive upload unreliable. ElevenLabs history URLs are zero-cost, durable, and the audio is already there.

#### Error Handling

- If `api.elevenlabs.io` is unreachable, write status note to the Notion record's メモ field and continue (Notion record stays, audio fields remain empty)
- If `.env` is missing or values are placeholders in autonomous mode, mark the record as failed and exit — do NOT prompt
- If the API returns 200 but `history-item-id` header is absent (unexpected), log the request-id to メモ field for manual lookup

### Step 7: Suggest Next Action (interactive mode only)

When run interactively, suggest **one** follow-up action:

- "同じ原文で、X投稿用の短縮版も作れますがいかがですか？" (Same source, different platform)
- "別の原文をランダムに選んで、同じ方針でリライトしましょうか？" (Different source, same settings)
- "ターゲットを変えて、30代会社員向けのバージョンも作れます。" (Different target audience)

**In autonomous (cloud routine) mode, skip this step entirely** — print a 1–2 line summary (article title / platform / character counts / Notion page URL) and exit.

---

## Scheduled Task Configuration (Claude Code `/schedule` cloud routine)

For fully automated daily execution via Claude Code's `/schedule` skill (remote agent on Anthropic cloud):

### Trigger prompt

The exact prompt registered with the routine lives in `trigger-prompt.md` at the repo root. That is the source of truth — keep it in sync with this doc.

### Routine config

- **Cron:** `0 21 * * *` UTC = **06:00 Asia/Tokyo daily**
- **Model:** `claude-sonnet-4-6`
- **Sources:** this private GitHub repo (cloned into the routine's workspace per run)
- **MCP connectors:** Notion + Google Drive (both must be connected on the user's claude.ai account)
- **Credentials:** Read from `.env` in the cloned repo at runtime (repo MUST stay private)

### Why a private repo

The cloud routine has no access to the user's local filesystem or local OS env vars. The skill's 450 source files and the ElevenLabs credentials must travel via the cloned repo. Keeping the repo private is the security boundary.

---

## Notion Database Usage Guide

### For Content Review

1. Open the "リライトスクリプト" database in Notion
2. View in **Table view** — both Plan A and Plan B text columns are visible
3. Click any cell in "リライト本文" or "リライト本文B" to select and copy the text
4. Set the "採用" field to indicate your decision:
   - **A案** — Use Plan A
   - **B案** — Use Plan B
   - **両方** — Use both
   - **不採用** — Reject both
   - **未判定** — Not yet reviewed
5. Set "ステータス" to "使用済み" after publishing

### Recommended Notion Views

Create filtered views for efficient workflow:
- **未判定** view: Filter by 採用 = 未判定 (review queue)
- **採用済み** view: Filter by 採用 = A案 OR B案 OR 両方 (approved content)
- **投稿先別** view: Group by 投稿先 (content by platform)

---

## File Inventory

```
.
├── INSTRUCTIONS.md          ← This file (design doc)
├── README.md                ← Setup + git push instructions
├── trigger-prompt.md        ← Autonomous prompt registered with /schedule routine
├── .env                     ← ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID (private repo)
├── .gitignore
└── skill/
    ├── SKILL.md             ← Runtime workflow definition (read by the cloud agent each run)
    └── references/
        ├── index.md         ← Master index of all source texts
        ├── ch01_自由と時間.md ← Set 1: Philosophy (001–010)
        ├── ...               ← (ch02–ch10)
        ├── s01_ChosenOne.md  ← Set 2: Spiritual (101–110)
        ├── ...               ← (s02–s15)
        ├── t01_学校教育の嘘.md← Set 3: Society (251–260)
        ├── ...               ← (t02–t10)
        ├── v01_学校教育の嘘Vol2.md ← Set 4: Society Vol.2 (351–360)
        └── ...               ← (v02–v10)
```

Total: **450 source texts** across **45 reference files**

# SNS Rewrite Skills — Orchestrator

このディレクトリは Claude Code の標準スキルディスカバリ位置（`.claude/skills/<name>/SKILL.md`）に従う。

## レジストリ

| Sub-skill | Path | 投稿先 | Cloud routine | Cron | Trigger prompt |
|---|---|---|---|---|---|
| Short video | `.claude/skills/sns-rewrite/SKILL.md` | `ショート動画` | `trig_0146gAGPHZ44FndRHDcuKBjm` (`SNS Rewrite Daily`) | 06:00 JST daily | [trigger-prompt.md](../../trigger-prompt.md) |
| X (Twitter) | `.claude/skills/sns-rewrite-x/SKILL.md` | `X` | （未登録 / manual-only） | — | [trigger-prompt-x.md](../../trigger-prompt-x.md) |

## アーキテクチャ

```
┌────────────────────────────────────────────────────────────┐
│ Trigger prompt (orchestration only)                         │
│ - trigger-prompt.md / trigger-prompt-x.md                   │
│ - cwd・自律ルール・ステップ列のみ                              │
└─────────────┬──────────────────────────────────────────────┘
              │ reads
              ▼
┌────────────────────────────────────────────────────────────┐
│ Skill (single source of truth for rules)                    │
│ - .claude/skills/<name>/SKILL.md                            │
└─────────────┬──────────────────────────────────────────────┘
              │ delegates I/O
              ▼
┌────────────────────────────────────────────────────────────┐
│ Tools / Workflows                                           │
│ - tools/fetch-sources.ps1   (RSS → .tmp/)                   │
│ - tools/notion-create-page.ps1  (REST POST → Notion)        │
│ - workflows/cite_authentic_source.md  (出典選定SOP)         │
│ - reference/authentic-sources.md  (4 RSS + 3 静的の登録簿)   │
└─────────────┬──────────────────────────────────────────────┘
              │
              ▼
       Notion DB 087eff43-caa5-41ff-944e-7982f68faef8
       (差別化は「投稿先」プロパティ)
              │
              ▼
       audio-filler (GitHub Actions @ 06:15 JST)
       ─ 投稿先 == "ショート動画" のエントリのみ音声生成
```

## Cross-cutting workflows

- [workflows/cite_authentic_source.md](../../workflows/cite_authentic_source.md) — 全サブスキルが本文に出典1件を付与するための共通SOP。4つのRSS（内閣府／厚労省／Yahoo社会／NHK）から取得し、A案・B案で異なる媒体を引用、URLは `出典URL_A` / `出典URL_B` に格納する。

## Property invariants (all sub-skills must honor)

- All sub-skills write to the **same Notion DB** `087eff43-caa5-41ff-944e-7982f68faef8`.
- Each sub-skill sets `投稿先` to a **distinct, fixed value** (`ショート動画`, `X`, ...).
- Common columns produced by every sub-skill: タイトル / リライト本文 / リライト本文B / 投稿先 / ターゲット / 文体 / 原文番号 / 文字数 / 文字数B / 採用 / ステータス / 出典URL_A / 出典URL_B / 出典媒体.
- 軸A（ターゲット10個）と 軸B（文体5個 / 型3個）は全サブスキルで共通。
- 軸C（投稿先）はサブスキルごとに固定値。

## Side-effect contract

- 音声生成の対象は **`投稿先 == "ショート動画"` のエントリのみ**。
- audio-filler（`tools/audio-filler.sh` / `tools/audio-filler.ps1`）はこの条件で Notion クエリをフィルタする。
- X など他プラットフォームのエントリは `音声URL_A` / `音声URL_B` が空のままで完結する。

## Notion REST integration（MCPは使わない）

サブスキルは MCP の `notion-create-pages` を使わず、REST API を直接叩く。

- ローカル：`pwsh -File tools/notion-create-page.ps1 -PropertiesJson '<flat>'`
- クラウド：`POST https://api.notion.com/v1/pages`（typed JSON を直接組み立て）

理由：MCP サーバが提供する20以上のツールスロットのうち、本リポジトリは `create-pages` と `query`（重複チェック用）の2つしか使わない。REST に切り替えてスロット消費を最小化する。

## Adding a new platform sub-skill

1. `.claude/skills/<name>/SKILL.md` を作成（既存2つを参照）。
   - frontmatter の `name` をディレクトリ名と一致させる
   - 固定仕様の `投稿先` を新しい値に
   - 文字数・トーンルールをそのプラットフォーム向けに上書き
   - §1〜§4.5 と §5 の Notion マッピングは原則そのまま
2. `trigger-prompt-<name>.md` を作成（既存2つを参照）。**ルールの再記述はしない**（重複は drift の温床）。
3. （任意）クラウドルーチンを `RemoteTrigger` で登録。既存ルーチンの cron と被らない時刻にする。
4. `audio-filler` が音声生成すべき投稿先を増やす場合は `tools/audio-filler.sh` と `tools/audio-filler.ps1` のフィルタを更新（多くの場合は不要）。

## Platform spec catalog（新規サブスキル作成時の参考）

| 投稿先 | 文字数 | キースタイル | サブスキル |
|---|---|---|---|
| `ショート動画` | 300〜400字 | 冒頭1〜2文に強いフック。60秒で読み切れる量。感情の起伏（共感→転換→締め）。 | `.claude/skills/sns-rewrite/SKILL.md`（実装済み） |
| `X` | 400〜500字 | 5〜7段落構成（フック→共感→型固有の中核→反転→哲学者引用→解釈→出典→静かなCTA）。3つの型（A型・数値計算／B型・自己診断＝基準／C型・想起）から異なる2つでA/B生成。 | `.claude/skills/sns-rewrite-x/SKILL.md`（実装済み） |
| `Threads` | 350〜500字 | 冒頭は問いかけ／断言で「自分のことだ」と感じさせる。締めは余韻（共感／希望）。改行を寛容に。 | 未実装 |
| `ブログ` | 600〜700字 | 段落末ごとに次へ引き込むフック。見出しは付けず本文のみ。具体的なエピソードを織り交ぜる。 | 未実装 |
| `YouTube台本` | 400〜600字 | 書き言葉→話し言葉に変換（〜なんですよね、〜じゃないですか）。間（ま）を作る改行。リスナーが頷けるリズム。 | 未実装 |
| `Reels字幕` | 1行10〜15字 | 短く切れのいいフレーズでテンポ維持。画面で読みやすく。 | 未実装 |

全プラットフォーム共通：軸A（ターゲット10個）・軸B（文体／型）。原文は `skill/references/` の450本から選ぶ。Notion DB は同一、`投稿先` プロパティで仕分ける。

## Notion DB property reference

データソース ID: `087eff43-caa5-41ff-944e-7982f68faef8`

| プロパティ | 型 | 値 |
|---|---|---|
| タイトル | title | 原文タイトル |
| リライト本文 | rich_text | A案本文 |
| リライト本文B | rich_text | B案本文 |
| 投稿先 | select | `ショート動画` / `X` / `Threads` / `ブログ` / `YouTube台本` / `Reels` |
| ターゲット | select | 軸Aの10個 |
| 文体 | rich_text | `"A: <文体> / B: <文体>"` |
| 原文番号 | rich_text | `"原文XXX"` |
| 文字数 | number | A案文字数 |
| 文字数B | rich_text | B案文字数（文字列） |
| 採用 | select | `未判定` / `A案` / `B案` / `両方` / `不採用` |
| ステータス | select | `未使用` / `使用済み` / `失敗` |
| 音声URL_A | rich_text | ショート動画のみ書き込まれる（audio-fillerが埋める） |
| 音声URL_B | rich_text | 同上 |
| 出典URL_A | url | A案で引用したauthentic sourceの完全URL（[workflows/cite_authentic_source.md](../../workflows/cite_authentic_source.md) 参照） |
| 出典URL_B | url | B案で引用したauthentic sourceの完全URL |
| 出典媒体 | rich_text | `"<A案媒体名> / <B案媒体名>"`（例：`"NHK / 厚労省"`） |
| メモ | rich_text | ユーザー記入用 |

**注：`出典URL_A` / `出典URL_B` / `出典媒体` の3プロパティはNotion UIから手動で追加する必要がある**（このリポジトリのコードでは作成しない）。データソース ID `087eff43-caa5-41ff-944e-7982f68faef8` のページを開き、Property → Add a property で URL / URL / Text 型として追加する。

# context-hygiene 点検記録 — full scope (2026-06-09)

スコープ: 全部（5次元）。点検 read-only → 司令官 GO（選択肢 C）で破壊的クリーンアップまで実施。
ツール: `tools/context_hygiene/footprint.py`（CR-159 で採用・本日 baseline 記録）。

## 計測サマリ（実施前→後）

| 源 | bytes | ~tok | 予算比 | 所見 |
|---|--:|--:|--:|---|
| `CLAUDE.md`(root) | 4,919 | 1,415 | （合算） | 健全 |
| `.claude/CLAUDE.md`(惑星核) | 10,500 | 2,078 | **41.6%** /5,000tok | 余裕あり |
| `memory/MEMORY.md`(index) | 731 | 202 | **3.0%** /24.4KB | 理想 |
| skill frontmatter ×3 | 2,409 | 318 | — | 健全 |
| **合計** | 18,559 | **4,013** | | |

footprint 台帳 baseline = `docs/context_hygiene/footprint_ledger.json`（1 snapshot）。

## 5次元 所見

### 次元1: 自動ロード footprint — ✅ 健全（是正不要）
惑星核 41.6%・MEMORY 3.0% と両予算に余裕。固定費肥大なし。

### 次元2: MEMORY 衛生 — ✅（1件圧縮実施）
index 731B・5行・全1行・消化済/重複/誤り 検出ゼロ。topic `video-automation.md` が 19.9KB と重量級 → **圧縮実施（非破壊）: 19,893→14,057B (-29%)**。重複していた PS gotcha（変数名大小非区別）を1本化、廃止経緯（旧 -Auto / dead 関数 / 字幕v3 詳細＝Filmora で superseded / TTS 見送り調査）を簡潔化。全操作的事実・パス・数値・フラグ名・gotcha は保持。

### 次元3: 滞留・オーファン — 🧹 掃除実施
| 対象 | 実施 |
|---|---|
| `.tmp/`（28MB/106ファイル・gitignored） | **一括削除**（regenerable・`.ps1` 2本=add-prop/backfill-captions も破棄＝司令官判断） |
| `logs/audio-filler.log`（Apr 29・gitignored） | **削除** |

### 次元4: アーカイブ候補 — 低優先（保持）
`docs/handoffs/` 3件は §8-2 設計上の累積想定 → 保持。明確な superseded 戦略文書なし。

### 次元5: 物理・gitignore 衛生 — 🧹 整理実施
| 対象 | 実施 |
|---|---|
| `sirius_profile.jpeg`（旧アイコン・不採用・handoff §5 が削除可否質問） | **削除** |
| `Make_second_image_first_color_*.jpeg`（用途不明の中間物） | **削除** |
| `prfofile_hakuten_white-gold.jpeg`（524KB tracked） | **維持**（handoff 確認の結果＝確定ブランドアイコン。当初フラグは誤りと判明） |
| `.gitignore` に `__pycache__/` 不在 | **1行追加**（context-hygiene 導入で py 実行増） |

> 削除した `.tmp`/`logs`/root画像はすべて untracked/gitignored ＝ `git status` 空。リポ履歴に影響なし。

## コミット対象（tracked 変更のみ）
- `.gitignore`（+`__pycache__/`）
- `docs/context_hygiene/footprint_ledger.json`（baseline）
- 本記録 `docs/verification/2026-06-09-context-hygiene-full.md`

memory `video-automation.md` の圧縮はリポ外（`~/.claude/.../memory/`）＝非コミット。

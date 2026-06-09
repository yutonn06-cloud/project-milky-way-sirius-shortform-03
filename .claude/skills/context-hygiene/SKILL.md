---
name: context-hygiene
description: >-
  あなたの衛星リポジトリの「Claude が毎セッション自動で読み込むコンテキストのトークン肥大」と
  「不要ファイルの滞留」を固定ルーブリックで点検し、表形式で削減・整理を提案する project-agnostic スキル。
  トリガー例:「コンテキストが重い」「トークンを食いすぎ」「読み込みを軽くしたい」「MEMORY.md を圧縮」
  「不要ファイルを整理/アーカイブ」「滞留ファイルを洗い出す」「自動ロードの footprint を見たい」
  「context hygiene を回して」。
  自動ロード footprint / MEMORY 衛生 / 滞留・オーファン / アーカイブ候補 / 物理・gitignore 衛生 の
  5次元を計測値付きで表で返す。点検は read-only。圧縮(非破壊)は提案＋実施可、削除/アーカイブ(破壊的)は
  必ず人間/司令官 GO（各衛星 governance の破壊的操作規律に従う）。
  NOT: 実行時コード速度(perf-audit 等)・パイプライン疎結合監査(pipeline-audit 等)・
  ファイルの無断削除/アーカイブ(GO 必須)・人間専任ゲートの代替。
---

# context-hygiene — コンテキスト/トークン衛生 点検スキル

衛星リポジトリの **「Claude が毎セッション自動で読み込むもの」のトークン footprint** と **不要ファイルの滞留**を、固定ルーブリックで点検し、必ず**計測値付きの表形式**で返す。狙いは「読み込み速度の維持・トークン過剰消費の防止・記憶の取りこぼし解消」。

> **fleet baseline スキル（CR-COSMOS-20260608-157）**：本スキルは Thuban 衛星（第1衛星・闇の女霊脈譚）が発明した context-hygiene を **project-agnostic に一般化**し、艦隊 baseline（greenfield 誕生時 全衛星へ自動 seed）へ昇格させたもの。点検対象の自動ロード源（root `CLAUDE.md` + `.claude/CLAUDE.md` 惑星核 + `MEMORY.md` + skill frontmatter）は REQ-COSMOS-005 §4-3 二層分離 + auto-memory ゆえ全衛星共通。各衛星固有の §条番号・パス規律は、その衛星自身の `CLAUDE.md` / 惑星核の更新規律に読み替えること。

**点検は read-only。** 提案には2種ある：
- **圧縮（非破壊）**＝index 短縮・本文の詳細退避・重複統合など。情報を失わないので**提案＋実施まで可**。
- **削除・アーカイブ（破壊的）**＝ファイルの delete / `archive/` 移動。**無断削除禁止**（自動 rollback なし）に該当するため**点検・提案までが責務、実行は必ず人間/司令官 GO**（各衛星 governance の破壊的操作規律に従う）。

## 点検スキルの棲み分け（衛星に併設スキルが在れば）

| スキル | 問い |
|---|---|
| `pipeline-audit`（在れば） | 壊れていないか（構造の健全性） |
| `perf-audit`（在れば） | コードを速く回せるか（実行時性能） |
| **context-hygiene（本書）** | Claude の読み込みが軽いか（トークン衛生・滞留整理） |

3者は直交。本スキルは「コードの実行速度」ではなく「**Claude のコンテキスト読み込み量**」を見る。併設スキルは衛星ごとに有無が異なる（本スキルは単独でも完結する）。

## いつ使うか

- セッション開始時のコンテキストが重い・トークン消費が早いと感じたとき。
- MEMORY.md が上限超過の警告を出したとき（index が一部しか読まれない実害）。
- `_inbox/` `tmp/` `logs/` `archive/` 等の滞留が気になったとき。
- 大きなドキュメントを追加した後の footprint チェック。
- 「消化済（superseded）」になった戦略文書・handoff・検証記録の整理前点検。

## 全衛星共通の自動ロード源（点検の出発点）

毎セッション自動注入され、トークン予算を直接消費するもの（REQ-005 二層分離 + auto-memory ゆえ全衛星共通）：

| 源 | 所在 | 予算/制約 |
|---|---|---|
| root 起動ドキュメント | `CLAUDE.md` | 衛星セッションの起動文。`.claude/CLAUDE.md` と**合算で評価** |
| 惑星核（脳幹） | `.claude/CLAUDE.md` | **5,000 トークン上限**（REQ-011 v1.2 §6 I5・更新規律で肥大抑制） |
| 自動記憶 index | `memory/MEMORY.md` | **上限 24.4KB**（超過すると一部しかロードされない＝記憶の取りこぼし） |
| 記憶トピック | `memory/*.md` | recall 時に `<system-reminder>` で注入。消化済/誤り/重複が溜まる |
| skill description | `.claude/skills/*/SKILL.md` frontmatter | 全 description が起動時に列挙される。冗長だと固定費が増える |

> 注: handoff 規律（1 session = 1 file）で `docs/handoffs/` は増え続ける設計。これらは**自動ロードされない**ので footprint には乗らないが、滞留・アーカイブ候補の対象。

## 固定ルーブリック（5次元・必ず全部 表で返す）

スコープを決めたら以下5次元を**それぞれ表で**埋める。所見が無い次元も「該当なし」と明記。**推測でなく計測値**（バイト数/行数/概算トークン）を入れる。

> 概算トークンの目安: 日英混在で **≈ 文字数 ÷ 3〜3.5**（日本語は密度が高い）。正確さより「予算に対して何倍か」の桁感を掴むのが目的。MEMORY.md は KB を直接見れば上限 24.4KB と比較可。

### 次元1: 自動ロード footprint（Auto-load Footprint）
毎セッション注入される各ファイルのサイズと予算超過。
| ファイル | 実測(KB/行) | 概算トークン | 予算 | 予算比 | 所見 |

- `.claude/CLAUDE.md` は 5,000 トークン上限に対する比を必ず出す。
- root `CLAUDE.md` + `.claude/CLAUDE.md` の**合算**も出す。
- skill frontmatter description の合計文字数も1行で。

> **footprint 台帳ツール（推移を数値＋視覚で追う）**: 手計測の代わりに
> `python tools/context_hygiene/footprint.py` を使う（本スキルに同梱・baseline seed 時に `tools/context_hygiene/footprint.py` へ配置）。`measure`＝現在値 JSON、
> `snapshot --note "<圧縮の説明>"`＝計測して台帳追記＋前回比レポート、
> `report [--md --out <path>]`＝最新 vs 前回 + 推移スパークライン。台帳 =
> `docs/context_hygiene/footprint_ledger.json`（git 追跡）。**圧縮を実施したら
> 必ず `snapshot` を打つ**——これで次回「何バイト/何% 減ったか」がゲージとトレンドで出る。
> MEMORY.md は repo 外（`~/.claude/projects/<repo>/memory/`）だがパスは自動導出。

### 次元2: MEMORY 衛生（Memory Hygiene）
MEMORY.md の上限と index 行の規律、トピックファイルの鮮度。
| 項目 | 現状 | 規律 | 是正(圧縮/退避/削除) |

検出パターン:
- **MEMORY.md 上限超過**: 24.4KB 超 → index エントリを **1行 ≤ ~200字**に短縮、詳細は各トピックファイルへ退避。圧縮は非破壊＝実施可。
- **消化済（★消化済 / superseded）記憶**: 本文に「消化済」「superseded by」と明記された index 行 → 1行サマリへ縮約、または topic 削除（削除は GO）。
- **重複記憶**: 同主題の topic が複数 → 統合提案（統合＝編集、元削除＝GO）。
- **誤り記憶**: 現状コードと矛盾する記憶（recall は書かれた時点の真実）→ 検証して訂正/削除提案。

### 次元3: 滞留・オーファン（Staleness & Orphans）
作業 scaffolding が消えずに残っているもの（`logs/` `tmp/` は disposable）。
| 場所/ファイル | 種別 | 最終更新の鮮度 | 滞留理由 | 是正案 |

検出パターン:
- `_inbox/` の取込済み残骸（manual-ingest 後の未掃除）。
- `tmp/` `.tmp/` `logs/` の肥大（gitignore 済みでもローカル肥大）。
- `_` 接頭辞の scratch（`_batch_*` `_smoketest_*` 等・`archive/` 行き想定）。
- 空の `_archive/`（正準は `archive/`）等の重複/オーファン構造。
- 古い `docs/verification/` `docs/handoffs/` の累積（自動ロードはされないがリポ肥大）。

### 次元4: アーカイブ候補（Archive Candidates）
役目を終えたが履歴として残す価値があるもの。delete でなく `archive/` 退避が適切なもの。
| ファイル | 役目終了の根拠 | 削除 or アーカイブ | 参照リンク切れ影響 |

検出パターン:
- superseded された戦略文書（後継が明示されている）。
- 古い SPEC バージョン（最新版が確定済み）。
- 消化済アジェンダ・完了 handoff。
- **判定**: 他文書から `[[link]]` 参照されている → 削除でなくアーカイブ（リンク切れ防止）。孤立 → 削除候補。いずれも実行は GO。

### 次元5: 物理・gitignore 衛生（Physical & gitignore）
リポジトリ物理サイズと追跡対象の妥当性。
| 項目 | 現状 | 規律 | 是正案 |

検出パターン:
- **追跡すべきでないものが tracked**: ログ・tmp・大容量バイナリ。gitignore 必須は `.env` `*.log` `tmp/` `.tmp/` `__pycache__/`。
- **大容量バイナリの混入**: repo root の `*.png` 等（制作アセットは外部ストレージが正本・参照は URL）。リポに置くべきか確認。
- `__pycache__/` `.pytest_cache/` の追跡漏れ。

## 実行手順

1. **スコープ確定**: 自動ロード footprint のみ / MEMORY のみ / リポ全体の滞留 / 全部か（不明なら AskUserQuestion）。
2. **計測を取る（推測しない）**:
   - **次元1（自動ロード footprint）は footprint 台帳ツールを優先**: `python tools/context_hygiene/footprint.py measure`（現在値）／圧縮実施後は `snapshot --note "..."`（台帳追記＋前回比レポート）。これで手計測不要・推移が残る。
   - サイズ（その他）: `Get-ChildItem` でファイルバイト数、`(Get-Content f | Measure-Object -Line).Lines` で行数（PowerShell）。または Bash で `wc -c`/`wc -l`。
   - MEMORY.md: 起動時の system-reminder 警告（"XX.XKB (limit: 24.4KB)"）が出ていればそれが一次情報（ツールも同値を出す）。
   - 概算トークン: 文字数 ÷ 3〜3.5 で桁感。
   - リポ物理: `git ls-files` で追跡対象、`Glob` で `_inbox/` `tmp/` `logs/` 等の滞留を列挙。
3. **多ファイル走査を Explore agent に fan-out**（コンテキスト節約・重要）:
   - 「消化済/superseded と明記された記憶・文書を全列挙」を1 agent、「`_` 接頭辞 scratch とオーファン構造を全列挙」を別 agent、「他文書から `[[link]]` 参照されている文書の被参照マップ」を別 agent。
   - agent には「パス + 根拠の最小引用 + 一言所見」だけ返させる。**削除/アーカイブの判断は本体（Claude）が**計測値と被参照影響を見て行う。
4. **5次元を表で合成**: 各提案を **圧縮（非破壊・実施可）/ 削除（GO 必須）/ アーカイブ（GO 必須）** に分類し、期待削減（KB/トークン）と参照切れ影響を添える。
5. **durable 記録**: 結果を `docs/verification/YYYY-MM-DD-context-hygiene-<scope>.md` に表で保存。圧縮を伴った場合は `footprint snapshot` を打ち、`footprint report --md --out docs/context_hygiene/FOOTPRINT_REPORT.md` で推移レポートも更新。
6. **2段で実行**:
   - **圧縮（非破壊）**: 方針確認後すぐ実施可（MEMORY.md index 短縮等）。情報を失わないことを必ず確認。
   - **削除/アーカイブ（破壊的）**: 一覧を提示し **人間/司令官 GO を取ってから**実行。GO 後も「対象を実際に開いて、記述と中身が食い違わないか」を確認してから（無断削除禁止）。

## fan-out の指針

- Explore agent は read-only 探索・被参照マップ作成に最適。**medium**（MEMORY/特定ディレクトリ）/**very thorough**（リポ横断・命名揺れ）。
- 独立な走査は1メッセージで複数 agent 同時起動。
- 計測値（サイズ/トークン）は本体が取り、agent には「該当パス + 根拠引用」のみ返させる。

## 不変の制約

- 点検は **read-only**。**削除・`archive/` 移動・git rm は人間/司令官 GO 必須**（無断削除禁止・自動 rollback なし）。
- **圧縮と削除を厳密に区別**: index 短縮・詳細退避・重複統合は非破壊＝実施可。ファイル消去は破壊的＝GO。
- **計測値で語る**。「重いはず」の推測禁止。測れないものは「未計測・推定」と明記。
- **被参照の確認**: `[[link]]` や相対パスで参照されている文書を消すとリンク切れ。削除前に被参照マップで確認し、参照ありはアーカイブを優先。
- 外部ストレージ一次資料・primary-source ディレクトリは対象外（衛星 governance の緊急エスカレーション対象）。
- `.claude/CLAUDE.md` の更新は各衛星の惑星核 更新規律に従う。圧縮提案も Class 判定の対象になりうる点を明記。
- 司令塔は各衛星の governance に従う（衛星により User 直接 / 中央経由が異なる）。

## Project-Specific Origin（一般化の出自）

- **発明元**: Thuban 衛星 `context-hygiene`（CR-COSMOS-20260606-147 で中央が観察候補登録・「他衛星 + 中央の context/token 管理に共通価値」「艦隊共通化の自然発生 第1事例」と評価）。
- **昇格**: CR-COSMOS-20260608-157 で fleet baseline へ先行昇格（2衛星需要を待たず 司令官承認＝baseline-eligibility 4基準 (d) で短絡）。一般化 = Thuban 固有の §条番号・WAT 起動・固有パス・姉妹スキル依存を除去し、全衛星共通の自動ロード源（二層 CLAUDE.md + MEMORY.md + skill frontmatter）に普遍化。
- **同梱ツール**: `footprint.py`（baseline seed 時に `tools/context_hygiene/footprint.py` へ配置・`_REPO_ROOT = parents[2]` ゆえこの install 深さを維持）。
- **正典**: skills.md §1（D7）/ §2-3（maintenance カテゴリ）/ fleet-baseline.json（SSoT）。

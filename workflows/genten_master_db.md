# Workflow: 原典マスターDB（A案）— 原文集の使用状況可視化

## 目的
原文集450本（`.claude/skills/sns-rewrite/references/` 45ファイル×10）を Notion の
「原典マスター」DB に台帳化し、**原文番号**をキーに Rewrite Script DB と突合して
各原典に **使用回数 / 最新ステータス / 最終使用日** をスタンプする。
これにより「どのテーマが枯れ、どこが手つかず（＝未使用原典＝次ネタ候補）か」を
体系的に可視化し、[[video-automation]] の下書きプールへ計画的に投入できるようにする。

## 構成要素
- **生成物CSV**：`docs/原典マスター.csv`（UTF-8 BOM・450行）。列＝`num / category / theme / title / sourcefile`。
  - 生成元：`.claude/skills/sns-rewrite/references/` の各 md（`## 原文NNN：タイトル` 見出しを抽出）。
  - 内訳：ch100 / s150 / t100 / v100 ＝ 450本（num 1–450）。
- **Notion 原典マスター DB**：`b363842b-500a-4ad8-9914-17fd89225193`
  （data_source `99e4e11d-fd4e-4601-b7bc-806f6b6f0cb4`）。
  親ページ「Rewrite for Short Video」(`2ebf7051-886d-808f-9844-d0da7ea65fd4`) 配下。
  - 列：タイトル / 原文番号(number) / カテゴリ(select) / テーマ(select) / sourcefile /
    使用回数(number) / 最新ステータス(select) / 最終使用日(date)。
- **突合元 Rewrite Script DB**：`087eff43-caa5-41ff-944e-7982f68faef8`。
  原文番号は `原文NNN`（ゼロ詰め3桁）テキスト。突合時に整数へ正規化。
- **ツール**：`tools/genten-master.ps1`（REST直叩き・ローカル専用）。

## 結合キー（重要）
`原文番号`。原典マスター側は NUMBER（1–450）、Rewrite Script 側は `原文NNN` テキスト。
ツールは両側から数字だけを抜き出して整数化し突合する（表記ゆれ吸収）。

## 手順
1. CSVを最新化（原文集を追加・改訂した場合のみ）。`docs/原典マスター.csv` を再生成。
2. 投入：`powershell -ExecutionPolicy Bypass -File tools\genten-master.ps1 -Import`
   - 冪等。既存の原文番号はスキップ。新規原文だけ追加される。
3. 突合スタンプ：`powershell -ExecutionPolicy Bypass -File tools\genten-master.ps1 -Sync`
   - Rewrite Script を全件取得 → 原文番号ごとに集計：
     - 使用回数 ＝ レコード件数
     - 最新ステータス ＝ 最新作成レコードの「ステータス」
     - 最終使用日 ＝ 最新作成レコードの作成日
   - 未使用の原典は 使用回数=0 / 最新ステータス=未使用 / 最終使用日=空 にリセット。
   - 変更がある行だけ PATCH（差分更新）。
4. 定期運用：`-Sync` を随時（週次目安）回せば最新の使用状況に追従する。

## ビュー（運用の入口）
- **カテゴリ別**：ボード（GROUP BY カテゴリ）— ch/s/t/v の俯瞰。
- **未使用原典（次ネタ候補）**：テーブル（FILTER 使用回数 = 0、SORT 原文番号 ASC）。
- **テーマ別カバレッジ**：ボード（GROUP BY テーマ）— どのテーマが枯れたか。

## 制約・gotcha
- **ローカル専用**：REST トークン（`.env` の `NOTION_TOKEN` / integration "SNS Audio Filler"）は
  クラウドsandboxに無い。`-Import`/`-Sync` はローカルでのみ動く。
- **PS 5.1 BOM**：`tools/genten-master.ps1` は UTF-8 **BOM付き**で保存すること。BOM無しだと
  PowerShell 5.1 が日本語のハッシュキーを文字化けして解釈しパースエラーになる（[[video-automation]] 同様）。
- **integration 共有**：新DBは作成後に Notion UI で "SNS Audio Filler" 連携を手動追加する必要がある
  （親ページ共有が直接共有でなく継承されないため）。2026-06-06 に追加済み。
- **レート制限**：Notion ~3 req/s。ツールは 120ms スリープ＋429リトライ済み。450件投入は約3–4分。

## 関連
- [[cloud-routines-architecture]] / [[video-automation]] / [[genten-master]]
- 出典・文体規律：`.claude/skills/sns-rewrite/SKILL.md`

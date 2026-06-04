---
project_id: project-milky-way-sirius-shortform-03
display_name: SNS Rewrite Automation
version: v1.0
status: draft
last_updated: 2026-06-04
---

# OPR-001：運用ガイド（Who / Rules）

**【ステータス：v0.1 充填（COSMOS 移行 Step 5・案 Y 手動充填・CR-COSMOS-20260604-141）｜版履歴 → [[decisions-log]] / git】**
**【最終更新：2026-06-04】**
**【Class：1（運用層・MVD 5/6）】**
**【依存：標準化レポート 20260604-sirius-shortform-standardization.md §2 MVD5 / §3】**

---

## 1. エージェント体制

- **Governance（中央 COSMOS）**：Strategic Commander（月次）/ Constitutional Judge（憲法）/ HQ SBG（予算）。
- **Work 層（衛星内）**：cloud_routine_orchestrator（日次起動）/ sns_rewrite（短尺 skill）/ sns_rewrite_x（X skill）/ tools/（PS+Python 決定論）。
- **司令塔**：User 直接（SNS 投稿 + Notion 採用判断）。PG=TBD（I5/Phase B）。

## 2. Work Layer パターン選択

**「標準」**を採用＝Workflow（trigger-prompt / cron）→ Agent（skills）→ Tools（決定論スクリプト）の中量級オーケストレーション（WAT）。単一巨大スクリプトを避け composable tools から組む。

## 3. ワークフロー（日次パイプライン）

1. **05:45 JST** GHA `sources-cache.yml`：4 RSS（内閣府/厚労省/Yahoo!News/NHK）を fetch → release asset（cloud WebFetch ブロック回避の proxy）。
2. **06:00 JST** cloud routine（trig_0146gAGPHZ44FndRHDcuKBjm）：原文選択（skill/references・Notion 7 日 dedup）→ A/B リライト（sns-rewrite・300-400字敬体）→ 出典付与（A/B 別媒体・本文裏取り）→ Notion REST POST（投稿先=ショート動画・音声 URL 空）。確認ゼロ・失敗時 Notion ステータス=失敗で graceful。
3. **06:15 JST** GHA `audio-filler.yml`：Notion 空音声 URL query → ElevenLabs TTS（A/B）→ Notion patch（localhost:8765 proxy URL）。
4. **X（手動）**：trigger-prompt-x.md で sns-rewrite-x（400-500字 3 型）→ Notion（投稿先=X）。

## 4. ハンドオフ規則

衛星セッション END で `docs/handoffs/YYYY-MM-DD-cosmos-sync-handoff.md` を生成（bridge-files-spec §5-5・5 セクション・50-100 行）。中央は recovery-checklist §2-0b で取り込み。

## 5. 品質ゲート（★出典整合がハード）

- **出典整合ハード品質ゲート**：実 RSS 4 source × 3 item → A/B 別媒体・**本文で裏取り**・**捏造引用 絶対禁止**（出典を煽りの免罪符にしない）。
- 文字数チェック（短尺 300-400字 / X 400-500字）。
- Notion 7 日 dedup（原文番号の重複回避）。
- **人間採用ゲート**：Notion 採用カラム（未判定 → A案/B案/両方/不採用）= 公開前の人間レビュー（Philosophy 1）。

## 6. エスカレーション規則

- Level 1：session 占有率 yellow（70%）/ 生成品質の一時低下 → Daily Digest。
- Level 2：session 占有率 red（85%）/ genre リスク発火（誤情報・BAN・政治炎上）→ escalation-queue.jsonl。
- Level 3：捏造引用検出 / PF 規約重大違反 / 憲法違反 → Constitutional Judge 通知 + Class 3。

## 7. 沈黙承認境界

自動（Class 0/1）= 原文選択・リライト生成・Notion write・ElevenLabs 音声・GHA 実行。人間必須 = SNS 投稿 / brand_voice・compliance 改訂（Class 3）/ 新 platform sub-skill（Class 2 30 秒ゲート）。

## 8. 外部実行ルール（Level 0/1/2）

- Level 0：ローカル生成 / RSS fetch / 原文選択 / Notion read。
- Level 1：Notion write / ElevenLabs TTS / GHA 実行。
- Level 2：SNS 投稿 API（人間専任・自動化封印）。

## 9. ELE 適用領域

A/B 2 案生成自体が ELE（実験的学習）＝採用カラムのフィードバックで文体軸・原文選択を改善。除外＝出典整合・捏造禁止（品質の絶対線）。

## 10. 改訂履歴

| 版 | 日付 | 改訂者 | 改訂内容 |
|---|---|---|---|
| v0.1 | 2026-06-04 | central-claude | 初版充填（Step 5・案 Y 手動・リーン巻きつけ）|

---
project_id: project-milky-way-sirius-shortform-03
display_name: SNS Rewrite Automation
version: v1.0
status: draft
last_updated: 2026-06-04
---

# PLN-001：事業計画書（How / When）

**【ステータス：v0.1 充填（COSMOS 移行 Step 5・案 Y 手動充填・CR-COSMOS-20260604-141）｜版履歴 → [[decisions-log]] / git】**
**【最終更新：2026-06-04】**
**【Class：2（衛星計画・変動層・MVD 4/6）】**
**【依存：REQ-001-requirements.md / 標準化レポート 20260604-sirius-shortform-standardization.md §2 MVD4】**

---

## 1. 現在フェーズ

次元上昇 Phase 1（autonomy 30%）。★既稼働 operational（cloud routine 06:00 JST 日次稼働）を governance 観点では Phase 1 から開始（リーン巻きつけ）。

## 2. ビジネスモデル

固定テンプレ原文のリライトによるショート動画 + X コンテンツの日次量産。現状は収益化前（コンテンツエンジン LIVE）。マネタイズは広告 / アフィリエイト動線を想定（怪しい系 vertical 親和）。

## 3. ロードマップ

| 段階 | 内容 | 時期 |
|---|---|---|
| 現状 | コンテンツエンジン日次稼働（短尺 cloud routine + GHA 音声）+ X 手動 | 稼働中 |
| 次 | マネタイズ着手（広告 / アフィリ動線の本文挿入方針・Class 2 ゲート）| Phase B |
| 次 | platform 拡張（Threads / YouTube / Reels の sub-skill 追加）| Phase 2 |
| 将来 | X パイプライン cron 化 + エンゲージ計測の KPI 化 | Phase B 以降 |

## 4. KPI

主要 = 日次リライト生成数 × 採用率（Notion 採用カラム）。将来 = SNS エンゲージ（再生 / 保存 / フォロワー増）。計測 = Notion DB 集計。

## 5. 予算計画

通貨予算 基本ゼロ運用（Vega 同型・session 占有率 70/25/5 三層配分）。実費は ElevenLabs TTS 少額のみ（governance/budget-policy.json）。マネタイズ到達後に収益連動予算へ拡張。

## 6. マイルストーン

- M1：艦隊登録 + scaffold 充填（2026-06-04・CR-140/141）✅
- M2：Phase B 着手（月次レビュー第 1 回）
- M3：マネタイズ動線の方針確定 + 初収益
- M4：platform 拡張（2 つ目の配信先）

## 7. リスク（要約・詳細は project-constitution.json risk_management）

誤情報拡散 / アカウント BAN / 捏造引用 / 政治的偏向炎上 / PF 規約変更。対策 = 出典 SOP + 人間採用ゲート + PF 規約月次追従。

## 8. 改訂履歴

| 版 | 日付 | 改訂者 | 改訂内容 |
|---|---|---|---|
| v0.1 | 2026-06-04 | central-claude | 初版充填（Step 5・案 Y 手動・リーン巻きつけ）|

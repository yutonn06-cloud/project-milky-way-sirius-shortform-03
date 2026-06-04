# Sirius 惑星核（.claude/CLAUDE.md）

**【ステータス：v0.1 初版充填（COSMOS 移行 I5・案 Y 手動充填）｜版履歴詳細 → [[decisions-log]] / git】**
**【最終更新：2026-06-04】**
**【関連 CR：CR-COSMOS-20260604-140（オンボード登録層）/ CR-COSMOS-20260604-141（Phase 0 移設 + GitHub rename + Step 5/6/I5 scaffold 充填）】**
**【Class：1（衛星 brain・全 agent session 冒頭参照・5,000 トークン上限脳幹）】**
**【依存：REQ-COSMOS-005 v1.0 §4-3（root CLAUDE.md と惑星核の二層分離）／REQ-COSMOS-011 v1.2 §6 I5（惑星核 5,000 トークン上限）】**

---

## §0 本書の位置づけ（5,000 トークン以内の長期記憶・脳幹）

本書は **Sirius 衛星の長期記憶・脳幹**。root `CLAUDE.md`（WAT framework 起動ドキュメント）とは**別レイヤー**（REQ-005 §4-3）。両者とも起動時に自動読込され並存する（トークン予算は合算評価）。

### §0-1 艦隊 identity 焼き込み 5 行（衛星単独 checkout 代替・正典 = identity.md）

1. **Fleet 名**：COSMOS（Command & Operations System for Multi-agent Orchestration and Scaling）
2. **Commander**：yutonn06（Universal Fleet CEO・個人ビジネス基盤を 10 年運用）
3. **Vibe**：技術判断ベース・対等性・煽動禁止（※艦隊横断 vibe。本衛星のコンテンツ brand_voice〔§3〕は怪しい系 vertical 固有で別物）
4. **Emoji policy**：司令官明示要求時のみ使用
5. **Continuity**：判断境界到達時に soul.md / decisions-log を参照、衛星固有作業時は本書をロード

---

## §1 衛星 ID（manifest 抜粋）

| 項目 | 値 |
|---|---|
| **project_id** | `project-milky-way-sirius-shortform-03` |
| **display_name** | SNS Rewrite Automation（codename: Claude Rewrite Agent）|
| **galaxy / star / domain / seq** | milky-way / sirius / shortform / 03 |
| **status / phase** | operational-live / Phase 1（自律度 30% / 閾値 50%/70%）|
| **GitHub** | yutonn06-cloud/project-milky-way-sirius-shortform-03（旧 sns-rewrite-automation・CR-141 で rename・public）|
| **司令官** | yutonn06-cloud |
| **発足（艦隊登録）** | 2026-06-04（CR-140 登録 / CR-141 scaffold）|
| **Mode** | 育成型 / ★既稼働 operational（リーン巻きつけ＝既稼働システムへのガバナンス後付け）|

---

## §2 commander_4_roles（衛星別解釈）

| 役割 | Sirius での発動条件 | 入口ファイル |
|---|---|---|
| **Constitutional Judge** | `project-constitution.json` 改訂時（Class 3・特に genre brand_voice / compliance）+ Phase B 完了後 v1.0 昇格承認 | `project-constitution.json` |
| **Strategic Commander** | 月次レビュー（R/Q universality 再評価 + KPI + PF 規約追従 + マネタイズ判断）| `migration-standardizations/[YYYYMM]-sirius-monthly-review.md`（起草予定）|
| **Escalation Judge** | scope-boundary 違反 / genre リスク発火（誤情報・BAN・捏造引用・政治炎上）| `governance/scope-boundary.json` + risk_management |
| **Passive Observer** | 日次 digest（cloud routine 06:00 生成状況 + Notion 採用状況）| Notion DB |

---

## §3 brand_voice 要点（★怪しい系 vertical 固有・Vega とは真逆）

**重要：** 本衛星の brand_voice は **怪しい系（自己啓発/スピリチュアル/陰謀/政治）vertical 固有**。soul.md §3 の艦隊横断 vibe（煽動禁止）は**業務コミュニケーションの規範**であり、本衛星の**コンテンツ作法には適用しない**。Vega（煽り/感情操作を禁止）とは真逆の vertical。

**tone / manner：**
- 敬体（です・ます）基調・危機感/覚醒/断定で読者を揺さぶる・冒頭 1-2 文に強フック・60 秒で読み切れる
- 共感 → 視点転換 → 締め の感情アーク。短尺 300-400字 / X 400-500字 3 型（統計恐怖/暴露怒り/時間切れ）

**Sirius 固有 forbidden_expressions（全文は project-constitution.json::brand_voice）：**
- 捏造引用（実在しない専門家・数値・研究の創作）/ 特定個人への誹謗中傷（構造批判は可）/ 医療・健康・金融の有害な断定助言 / PF 規約違反（差別・暴力扇動）/ 出典偽装
- ★ Vega の煽り語禁止（「今すぐ」等）は本衛星では**禁止しない**（genre 固有）

**Philosophy 4 衛星適用：** 通貨予算ゼロ運用（Vega 同型・session 占有率代替）。実費は ElevenLabs TTS 少額のみ。

---

## §4 agents 構造（Phase 別段階導入）

| Phase | agent | 役割 | 昇格状態 |
|---|---|---|---|
| **1** | sns_rewrite（skill）| ショート動画リライト 300-400字敬体 A/B | sirius-internal |
| **1** | sns_rewrite_x（skill）| X 400-500字 3 型 A/B/C | sirius-internal |
| **1** | cloud_routine_orchestrator | 日次自律オーケストレーション（06:00 JST）| sirius-internal |
| **2** | platform_subskill | Threads/YouTube/Reels 拡張 | planned |

**継承 skill**：なし（inherited_skills=[]・D 即時昇格 0 件・genre 汚染回避）

---

## §5 衛星固有規律（global 化対象外・scope_in=0）

| 規律 | 内容（要点）| reference |
|---|---|---|
| genre_native_rhetoric | 怪しい系の危機訴求/覚醒/感情訴求を vertical 固有作法として許容（Vega 反煽り継承せず）| brand_voice / skills |
| citation_integrity_hard_gate | 実 RSS 出典 SOP（A/B 別媒体・本文裏取り・捏造引用 絶対禁止）をハード品質ゲート化 | workflows/cite_authentic_source.md |
| two_stage_sandbox_split | cloud=テキスト+Notion / GHA=音声(ElevenLabs)+RSS proxy（サンドボックス制約回避）| .github/workflows/ |

**重要：** 規律はすべて `scope: sirius-internal-only`。genre 特異物の艦隊共通化は有害（汚染）ゆえ scope_in=0 で構造的に阻止。

---

## §6 衛星 KPI（暫定・月次レビューで再評価）

| 指標 | 目標値 |
|---|---|
| **主要 KPI** | 日次リライト生成数 × 採用率（Notion 採用カラム）|
| 目標値 | 日次 A/B 各1本（ショート動画）安定生成 + 採用率向上（暫定 draft）|
| 計測手段 | Notion DB 生成カウント + 採用カラム集計（将来 SNS エンゲージ追加）|

---

## §7 関連参照

**衛星内：** [project-manifest.json](../project-manifest.json) / [project-constitution.json](../project-constitution.json) / [governance/](../governance/) / [meta/foundation/](../meta/foundation/) / [CLAUDE.md](../CLAUDE.md)（WAT 起動ドキュメント・別レイヤー）/ .claude/skills/（sns-rewrite, sns-rewrite-x）/ workflows/cite_authentic_source.md

**cosmos-core 側：** soul.md / identity.md / user.md §2 / 00-START-HERE.md / `cosmos-core/registry/satellites/sirius-link.json` / `dependency-map.json::satellite_registry.project-milky-way-sirius-shortform-03`

---

## §8 セッション開始時参照順序

```
1. cosmos-core/identity/identity.md（5 行軽量焼き込み）  ← 中央 co-located 時。衛星単独時は §0-1 で代替
2. .claude/CLAUDE.md（= 本書）+ root CLAUDE.md（WAT）   ← 起動時に自動読込（両者並存・予算合算）
3. project-constitution.json::brand_voice / philosophy   ← 規範層参照（★ genre brand_voice は vertical 固有）
4. cosmos-core/identity/soul.md（業務 writing rules 違反検出時）
5. cosmos-core/identity/user.md（属性確認時）
```

**root `CLAUDE.md` との関係：** root `CLAUDE.md`（WAT framework・Workflows/Agents/Tools 起動ドキュメント）と本書（惑星核・脳幹）は二層構造で並存。両者とも自動読込先・トークン予算は合算管理。

---

## §9 更新規律・関連 CR

**更新頻度上限：** 四半期 1 回程度（月次レビュー結果 + Phase 遷移時）。

**v0.1 → v1.0 昇格条件：** Phase B 月次レビュー 3 サイクル完了 + Constitutional Judge 正式承認 + Phase C 昇格判定。

```
CR-COSMOS-20260604-140（オンボード登録層）/ CR-COSMOS-20260604-141（Phase 0 移設 + GitHub rename + Step 5/6/I5 scaffold 充填）
分類    ：Class 2（衛星 scaffold 後付け・リーン巻きつけ）/ constitution は Class 3（genre・CJ 承認）
発足    ：2026-06-04
依存規範：REQ-011 v1.2 §6 I5 / REQ-005 v1.0 §4-3
承認    ：Universal Fleet CEO（司令官）2026-06-04（実行許可 + genre 方針承認）

v0.1（2026-06-04）：初版充填（中央 案 Y 手動・既稼働 operational へのリーン巻きつけ）
```

---

**本書は Sirius 衛星の長期記憶・脳幹として、5,000 トークン以内で衛星固有現在地を提供する。root `CLAUDE.md`（WAT 起動ドキュメント）と二層構造で並存し、★既稼働 operational システムへのガバナンス後付け（リーン巻きつけ）という艦隊初パターンの衛星である。**

*Sirius 惑星核 (.claude/CLAUDE.md) v0.1 — 完*

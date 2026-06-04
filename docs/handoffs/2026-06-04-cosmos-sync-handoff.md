# COSMOS Sync Handoff — Sirius — 2026-06-04

> 衛星：`project-milky-way-sirius-shortform-03`（Sirius・第3衛星）
> 規律：[.claude/CLAUDE.md §8-2](../../.claude/CLAUDE.md) / bridge-files-spec §5-5。中央は recovery-checklist §2-0b で pull → 台帳反映（pull-only・二層分離。本衛星は cosmos-core を持たない）。
> **writeback 総評：HIGH**（Class 3 = constitution brand_voice 変更 + platform 撤退 = status 変化を含む）。

---

## (a) セッション要約

1. **艦隊統合の未 commit を整理し push**：司令官 WIP（運用ファイルの `.claude/skills/` 正準配置・旧 INSTRUCTIONS/skill/SKILL 削除）と中央配置 governance scaffold を 2 コミットに分離して push。GitHub を現在の中身に同期。
2. **§8-2 handoff 規律を惑星核に焼き込み**（Vega/Thuban パリティ完成。`sirius-link.json::handoff_protocol.satellite_side` が done）。
3. **X パイプラインを停止・休眠化**（司令官決定＝短尺専念）。claude.ai routine 無効化 + repo の operational/governance/constitution を X 休眠として更新。**X は削除せず温存（復活可能）**。
4. **短尺 cloud routine の破損を予防修正**：rename + 旧 `skill/SKILL.md` 削除により、ライブ短尺 routine が次回(明朝 06:00 JST)失敗する状態だった。プロンプトを新パス/新 repo URL に同期して回避。

## (b) 変更ファイル（+ writeback_level）

**operational（衛星内・Class 0/1・writeback: low）**
- `.claude/skills/sns-rewrite/SKILL.md` ほか運用一式：旧 `skill/SKILL.md` から正準配置へ移設（commit A）
- `.claude/skills/sns-rewrite-x/SKILL.md` / `trigger-prompt-x.md`：⏸停止・休眠バナー追記（温存）
- `.claude/skills/README.md`：X registry 行を「停止中・enabled:false」へ
- `.github/workflows/sources-cache.yml`：X cron(06:30) 言及を除去（05:45 fetch は短尺専用）
- `README.md`：X prompt / X レビュービューを dormant 注記
- `.gitignore`：`.tmp/` `credentials.json` `token.json` を除外追加

**governance / scaffold（中央配置・writeback: medium〜high）**
- `.claude/CLAUDE.md`：§8-2 新設（writeback: high）/ §3・§4 を X 休眠に更新（medium）
- `project-manifest.json`：agent `sns_rewrite_x` に `status:"dormant"` 付与（medium）
- `governance/planet-governor-config.json`：`x_cron_wiring` を停止・休眠に更新（low）
- `meta/foundation/{REQ,PLN,OPR,DIA}-001.md`：X を停止・休眠として注記（low）
- **`project-constitution.json` `brand_voice.manner` ＝ Class 3（writeback: high）**：X 句を休眠化 + `_platform_status_2026-06-04` 注記。**genre brand_voice 方針（危機訴求/煽り許容・Vega 反煽り非適用）は不変。**

**cloud routines（claude.ai・git 外・RemoteTrigger 操作）**
- `trig_01LYVZBHQSWRjyUcg2NVyPRM`（SNS Rewrite Daily X・06:30 JST）→ **enabled:false**
- `trig_0146gAGPHZ44FndRHDcuKBjm`（SNS Rewrite Daily・06:00 JST）→ プロンプトを `.claude/skills/sns-rewrite/SKILL.md` + 新 repo URL + 新 release-asset URL に同期（MCP 接続・DB id は不変）

## (c) COSMOS 同期項目（4 zone）

**(i) sirius-link.json 更新候補**
- `handoff_protocol.satellite_side`「§8-2 焼き込み予定」→ **done**（4357909）
- `status` / platform：**X = dormant、運用は短尺のみ**（platform 数 2→実働 1）
- KPI：主要 KPI（日次リライト生成 × 採用率）は短尺基準に集約（X 生成は停止）
- phase：Phase 1 のまま（自律度 30%・閾値変更なし）。git_status = 本 push で最新

**(ii) dependency-map 更新候補**
- `satellite_registry.project-milky-way-sirius-shortform-03`：active platform を「ショート動画のみ」に。X skill/routine は dormant 資産として保持

**(iii) D-class 昇格候補**：**0 件**（genre 汚染回避・inherited_skills=[] 維持）

**(iv) Phase B 月次レビュー参照項目**
- X 復活/廃止の最終判断（休眠の期限・KPI 再評価）
- brand_voice v0.1→v1.0 昇格時に X 句の最終形を確定（CJ 承認）
- 短尺 routine の prompt と repo `trigger-prompt.md` の drift 解消（下記 (e)）

## (d) git commit hash(es)

| hash | 内容 |
|---|---|
| `513a1de` | 運用ファイル `.claude/skills/` 正準配置（commit A） |
| `6509cd0` | COSMOS governance scaffold（commit B） |
| `4357909` | 惑星核 §8-2 handoff 規律 |
| `30abe1b` | X 停止・休眠化 + governance/constitution(Class 3) 更新 |
| （本ファイル） | 本 handoff（同 push に含む） |

すべて `origin/main`（`yutonn06-cloud/project-milky-way-sirius-shortform-03`）へ push 済。

## (e) 残務 / 申し送り

1. **repo `trigger-prompt.md` の drift**：repo 版は「クラウドで 4 RSS を直接 WebFetch」「REST 直叩き」と記すが、ライブ短尺 routine は実態に即し（WebFetch は .go.jp 等ブロック → GHA cache 経由、Notion は token 不在のため MCP 経由）正しく上書き済。repo の SKILL.md §5/§4.5 と trigger-prompt.md を「local=REST / cloud=MCP・GHA cache」で明確化するのが次の整理（Task3 候補）。
2. **README 軽微 staleness**：`README.md` 内に旧 repo URL `sns-rewrite-automation`（Security 節）と旧 OneDrive パス（Task Scheduler 例）が残存。今回スコープ外。
3. **次回稼働確認**：05:45 GHA sources-cache（新 release へ upload）→ 06:00 短尺 routine（新パスで稼働）→ 06:15 audio-filler。明朝のログで正常性確認推奨。
4. **X 復活手順**：各 X ファイル冒頭バナー記載。最低限 (1) バナー削除 (2) `RemoteTrigger update {enabled:true}` (3) governance/constitution の X 記述を稼働へ戻す。

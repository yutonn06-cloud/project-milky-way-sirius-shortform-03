---
project_id: project-milky-way-sirius-shortform-03
display_name: SNS Rewrite Automation
version: v1.0
status: draft
last_updated: 2026-06-04
---

# DIA-001：システム図（Overview 俯瞰層）

**【ステータス：v0.1 充填（COSMOS 移行 Step 5・案 Y 手動充填・CR-COSMOS-20260604-141）｜版履歴 → [[decisions-log]] / git】**
**【最終更新：2026-06-04】**
**【Class：2（俯瞰層・MVD 6/6）】**
**【依存：標準化レポート 20260604-sirius-shortform-standardization.md §2 MVD6 / fleet-pipelines.json（中央 topology 正典）】**

---

## 1. 全体構造図（repo フォルダ）

```
project-milky-way-sirius-shortform-03/
├── CLAUDE.md                 # WAT framework 起動ドキュメント（Workflows/Agents/Tools）
├── .claude/
│   ├── CLAUDE.md             # 惑星核（脳幹・5K token・本 scaffold）
│   └── skills/{sns-rewrite, sns-rewrite-x}/SKILL.md
├── project-manifest.json     # MVD 1（本 scaffold）
├── project-constitution.json # MVD 2（genre 憲法・Class 3・本 scaffold）
├── meta/foundation/{REQ,PLN,OPR,DIA}-001  # MVD 3-6（本 scaffold）
├── governance/{planet-governor-config, scope-boundary, budget-policy}.json  # 本 scaffold
├── skill/references/         # 原文コーパス約450本（ch/s/t/v）
├── workflows/cite_authentic_source.md  # 出典整合 SOP
├── tools/                    # PS+Python（audio-filler/audio-proxy/fetch-sources/notion-create-page）
├── .github/workflows/        # sources-cache.yml / audio-filler.yml
├── reference/authentic-sources.md  # RSS + 静的 ref レジストリ
├── trigger-prompt.md / trigger-prompt-x.md  # cron オーケストレーション
└── .env                      # secrets（gitignore）
```

## 2. エージェント階層図

```
User（司令官・SNS 投稿 + Notion 採用判断）
  └─ Governance（中央 COSMOS）：Strategic Commander / Constitutional Judge / HQ SBG
       └─ Work 層（衛星内）：
            cloud_routine_orchestrator（日次起動）
              ├─ sns_rewrite（短尺 skill）
              ├─ sns_rewrite_x（X skill）⏸停止中/休眠（2026-06-04〜）
              └─ tools/（決定論：音声/RSS/Notion POST）
```

## 3. データフロー図（日次パイプライン）

```
[05:45 GHA] RSS feeds(内閣府/厚労省/Yahoo/NHK) ─fetch→ release asset
                                                        │
[06:00 cloud routine] skill/references(450本) ─選択(Notion 7日dedup)→ A/Bリライト
        └─ 出典付与(A/B別媒体・本文裏取り・捏造禁止) ──→ Notion REST POST(投稿先=ショート動画)
                                                              │ (音声URL 空)
[06:15 GHA audio-filler] Notion query ─→ ElevenLabs TTS(A/B) ─→ Notion PATCH(音声URL)
                                                              │
                                              [人間] Notion 採用カラム判断 ─→ SNS 投稿(手動)

[⏸停止/休眠 2026-06-04〜] trigger-prompt-x → sns-rewrite-x(3型) → Notion(投稿先=X)  ※短尺専念・skill/prompt 温存・routine enabled:false
```

## 4. 状態機械（Notion 採用 / ステータス）

- 採用：未判定 → A案 / B案 / 両方 / 不採用（人間ゲート）
- ステータス：未使用 → 使用済み / 失敗（cloud routine 失敗時 graceful）

## 5. 外部接続図

```
Claude Code(cloud routine) ─REST→ Notion(SSoT・16 property)
GitHub Actions ─→ RSS feeds(proxy) / ElevenLabs(TTS)
ローカル tools/ ─→ audio-proxy(localhost:8765) / Notion REST
（AI Drive 不使用＝Notion-SSoT）
```

> 艦隊 topology の正典は `cosmos-core/registry/fleet-pipelines.json::satellites.milky-way-sirius-shortform-03`（daily_rewrite / audio_fill / x_rewrite）+ 生成図 `reports/diagrams/pipelines-sirius.md`。

## 6. 改訂履歴

| 版 | 日付 | 改訂者 | 改訂内容 |
|---|---|---|---|
| v0.1 | 2026-06-04 | central-claude | 初版充填（Step 5・案 Y 手動・リーン巻きつけ）|

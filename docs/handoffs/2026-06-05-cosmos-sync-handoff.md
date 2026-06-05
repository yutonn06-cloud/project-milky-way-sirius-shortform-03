# COSMOS Sync Handoff — Sirius — 2026-06-05

> 衛星：`project-milky-way-sirius-shortform-03`（Sirius・第3衛星）
> 規律：[.claude/CLAUDE.md §8-2](../../.claude/CLAUDE.md) / bridge-files-spec §5-5。中央は recovery-checklist §2-0b で pull → 台帳反映（pull-only）。
> **writeback 総評：MEDIUM**（運用 capability 変化＝「動画生成までフルオート化」。constitution / brand_voice は不変＝Class 3 なし。新 platform 着手・マネタイズなし）。

---

## (a) セッション要約

1. **字幕方針を転換**：焼き込み字幕は実用不足 → **仕上げは Filmora（字幕検出）**。make-video の既定を **VIDEO-ONLY（字幕なし）** にし、出力を**種類別サブフォルダ**（`字幕なし\`/`字幕あり\`/`srt\`/`投稿済\`）へ。captions/SRT/CapCut は opt-in に反転。
2. **★動画生成までフルオート化**：`-Auto` バッファモード（1回3カット×13/16時の2回＝最大6本/日を作り溜め）＋ **Windows タスクスケジューラ `Sirius-AutoVideo`**（毎日 13:00/16:00・ログオン時）。Notion 状態機械 **未使用→動画化済→使用済み**、`使用済み` は動画を `投稿済\` へ**自動アーカイブ**（＝再投稿防止）。実機（実タスク）で 3/3 カット・アーカイブ・書き戻し検証済。
3. **CapCut 連携ツール**（`build-capcut-draft.py`・pycapcut・thuban 参考）と **SRT 書き出し**を実装 → ただし運用は Filmora 採用のため**既定 OFF で残置**。
4. **音楽運用＝inbox 方式**：`add-music.ps1`（`_inbox\<mood>\` 投入 → 採番/リネーム/`_rename-map.txt`/移動）。**wav 等そのまま可**（make-video は全音声拡張子対応）、mp3 変換は `-ToMp3`。一旦は衛星別ライブラリ（共有化は保留）。
5. **X 台本の動画化（変化球）**を実装（火金・ローカル ElevenLabs TTS・X backlog 38本流用）→ ただし **X 原稿は読み物用で TTS が片言化**（長い数字/固有名詞詰め込み文）と判明 → **自動 X を停止（run-auto に `-NoX`）・手動キュレーションへ**。原文076 は `未使用` に戻し。

## (b) 変更ファイル（+ writeback_level）

**operational（衛星内・Class 0/1）**
- `tools/make-video.ps1`：video-only 既定 / 種類別フォルダ / `-Auto` バッファ / Notion 書き戻し＋自動アーカイブ / wav 対応 / X 変化球。rotation-state を **OneDrive→`%LOCALAPPDATA%\sirius-make-video\`** へ移設（OneDrive ロック回避＋リトライ）。(**writeback: medium**＝capability)
- `tools/run-auto.ps1`（新規）：スケジューラ用ランチャー（FFMPEG_DIR / UTF-8 ログ / 現在 `-NoX`）。(low)
- `tools/register-auto-task.ps1`（新規）：日次タスク登録（13:00/16:00・admin 不要）。(low)
- `tools/add-music.ps1`（新規）：BGM inbox 取込。(low)
- `tools/build-capcut-draft.py`（新規）：CapCut ドラフト注入・既定 OFF。(low)

**衛星ローカル環境（git 外）**
- Windows Scheduled Task **`Sirius-AutoVideo`**（13:00/16:00・現ユーザー）
- `%LOCALAPPDATA%\sirius-make-video\`：`rotation-state.json` / `last-x-date.txt`
- pip: **pycapcut 0.0.3**（+ uiautomation/comtypes/pymediainfo/imageio）を `py`(3.14) に追加
- Notion DB `Rewrite Script`：`ステータス` に option **「動画化済」** が自動追加

**constitution / governance**：変更なし（brand_voice 不変・Class 3 なし）。

## (c) COSMOS 同期項目（4 zone）

**(i) sirius-link.json 更新候補**
- `status`：operational-live 維持。
- **自律度**：パイプラインが「RSS→テキスト(cloud)→音声(GHA)→**動画 字幕なし(ローカル定期)**」まで自動化＝動画工程まで無人化の実績（Phase 1 自律度 30%→閾値 50% に向けた素材）。
- **KPI 見直し候補**：`採用率` は不使用化（司令官＝採用判断に意味を感じず／再利用防止が実需）。新 KPI 候補＝「日次 字幕なし動画 自動生成数 / バッファ消化（投稿数）」。
- `git_status`：HEAD `10a94d6`。

**(ii) dependency-map 更新候補**
- ローカル依存追加：pycapcut（CapCut・既定OFF）/ ElevenLabs ローカル TTS（X用・現在停止）/ Windows タスクスケジューラ / whisper.cpp（既存・opt-in）。
- **動画工程はローカル PC 必須**（元素材 数十GB がローカルのみ。クラウド/GHA 化は将来の独立案件）。

**(iii) D-class 昇格候補**：**0 件**（衛星固有・genre/ローカル環境依存で艦隊共通化は不適）。`add-music.ps1` のみプロジェクト非依存設計＝将来 fleet 共通化の余地あり（今回は昇格せず）。

**(iv) Phase B 月次レビュー参照項目**
- フルオート稼働率（PC-on 依存・StartWhenAvailable のキャッチアップ実績）。
- KPI 定義の差し替え（採用率 → 生成数/投稿数）。
- X 動画化の前処理（narration 向け短文化リライト）要否＝再開判断。

## (d) git commit hash(es)

```
10a94d6 run-auto: pause scheduled X auto-injection (-NoX)
34e8ba1 make-video: occasional X-format variety in -Auto (weekly, local TTS)
8a265be music: support wav (and any audio) for BGM end-to-end
c590acf add-music: transcode non-mp3 drops to mp3; harden final count
7049b36 add-music: inbox-based BGM ingest + exclude _inbox
b8cc3ff make-video: full-auto buffer mode (-Auto) + daily scheduler + Notion status pipeline
26e4f7f make-video: video-only default + Filmora flow; type-split folders; opt-in captions/SRT/CapCut
```

## (e) 残務 / 申し送り

- **★次回の本題（司令官指示）：TikTok のプロフィール / プロフィール設定 / 名前設定の再検討。**
- **X 動画化は保留**：原稿が読み物用 → TTS 片言化。再開するなら「長文を `。` で 2-3 分割・1文 ≤35字・数字/固有名詞を詰めない」narration 前処理の実装が前提。X 自体は休眠維持（[[x-pipeline-dormant]]）。
- **Notion `Rewrite Script` が UI で編集不可**との報告 → API/インテグレーションは編集可（確認済）。**「データベースをロック」UI トグルの解除は司令官のアプリ操作が必要**（API 不可）。
- **バッファ掃除待ち**：`字幕なし\` に本セッションのテスト（原文387 多数）＋片言の `auto_X原文076_*` 2本が残存。要一掃。
- **実運用観察**：明朝以降の無人サイクル（ショート 3×2/日）＋ 手動投稿 → Notion `使用済み` → 自動アーカイブ の回り具合。
- CapCut ツールは残置・既定 OFF（Filmora 運用へ）。

---

*Sirius COSMOS Sync Handoff 2026-06-05 — 完*

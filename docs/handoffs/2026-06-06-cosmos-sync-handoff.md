# COSMOS Sync Handoff — Sirius — 2026-06-06

## (a) セッション要約
1. TikTokアカウントのブランド刷新（`@kokurenha`「銀河蓮」→ **Hakuten Life** `@hakuten.life`・X `@hakuten018` と統一・新アイコン採用）。
2. 動画パイプラインを **1案＋下書きプール方式** へ再設計（1リライト=1動画=1レコード・音声ローカル化・台帳＝完成動画のみ）。
3. クラウド短尺ルーチン／正典SKILL.md／手動スキルを 1案＋下書きへ統一切替、GHA音声フィラー停止。

## (b) 変更ファイル
- `prfofile_hakuten_white-gold.jpeg`（新規）— 確定アイコン/将来ブログロゴ（白×金 羽根エンブレム）。writeback: low
- `sirius_profile.jpeg`（新規・不採用）— 旧アイコン候補（薄い金）。破棄候補。writeback: low
- `.claude/skills/sns-rewrite/SKILL.md` — A/B 2案 → **1案＋ステータス=下書き** に全面改訂。writeback: medium
- `trigger-prompt.md` — 1案＋下書き＋MCP/GHAキャッシュの実態に整合。writeback: medium
- `tools/make-video.ps1` — `-Auto` を下書きプール消費→ローカルTTS→動画→`Set-NotionPromoted`（動画化済＋ファイル名）に作替。`Get-DraftShortEntries`/`Set-NotionPromoted` 追加。アーカイブMove-Itemを `Invoke-WithRetry`＋skipで堅牢化。writeback: high
- `tools/notion-create-page.ps1` — スキーマに `ファイル名` 追加。writeback: low
- `.github/workflows/audio-filler.yml` — schedule停止（手動dispatchのみ）。writeback: medium
- Notion DB「Rewrite Script」（087eff43…）— `ファイル名` 列追加、`下書き`ステータス運用開始。writeback: high（外部状態）
- claude.ai routine `trig_0146gAGPHZ44FndRHDcuKBjm` — プロンプトを1案＋下書きへ更新（RemoteTrigger）。writeback: high（外部状態）

## (c) COSMOS 同期項目（4 zone）
(i) **sirius-link.json 更新候補**：
   - 出力先アカウント識別子＝Hakuten Life / `@hakuten.life`（旧 @kokurenha）。
   - KPI 計測：採用カラム運用が「下書き→動画化済→使用済み」状態機械へ移行（A/B生成数→1案生成数）。日次 A/B 各1本目標は**日次1案×N本（バッファ）**に読み替え。
(ii) **dependency-map 更新候補**：cloud routine の出力契約が変化（音声URLを書かない／ステータス=下書き）。GHA audio-filler 依存を除去。
(iii) **D-class 昇格候補**：0件（衛星固有・genre 汚染回避継続）。
(iv) **Phase B 月次レビュー参照**：パイプライン再設計（自律度・運用簡素化）と新ブランドのエンゲージ初期値を次回レビューで評価。

## (d) git commit hash(es)
- 未コミット（司令官の指示待ち）。コミット時に追記。

## (e) 残務 / 申し送り
1. **明朝 06:02 JST の実地検証**：新ルーチンが `ステータス=下書き` で1案レコードを作るか。続いて 13:00/16:00 のローカル `Sirius-AutoVideo` が下書きを動画化→台帳昇格するか確認。
2. **台帳ビューのフィルタ**（司令官UI作業）：「ステータス が 下書き でない」を追加 → 完成動画だけ表示。
3. **不要Notion列の削除（要承認・破壊的）**：リライト本文B / 文字数B / 音声URL_A,B / 採用 / ターゲット / 文体 / 出典URL_B。**X在庫38本のB案データが消える**ため、消してよいか／先にCSVエクスポートするか未回答。出典URL_A・出典媒体は compliance で残す。
4. 旧 dead 関数（Get-AutoEntries 他）と make-video 手動パスの音声URL依存はクリーンアップ余地（低優先）。
5. 旧アイコン `sirius_profile.jpeg` の削除可否。
6. X自動投稿は休眠継続（`-NoX`）。今回はブランド名統一のみ。

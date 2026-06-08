クローン済みリポジトリのルート (cwd) で動作してください。本日分のSNSリライト（ショート動画）を1本、自律モードで生成します。

**Single source of truth for rules:**
- `.claude/skills/sns-rewrite/SKILL.md` — 文体・敬体・タメ語禁止・出力フォーマット（**最初に全文読み、これに従う**）
- `workflows/cite_authentic_source.md` — 出典付与の共通SOP
- `reference/authentic-sources.md` — 4本のRSS + 3つの長期文脈リファレンス
- `skill/references/*.md` — 原文集（45ファイル・450本）

トリガープロンプトはオーケストレーションのみを担う。トーン規則は skill ファイルに集約済み。**ここで再記述しない**（重複は drift の温床）。

【新モデル：1案＋下書きプール（2026-06-06〜）】
このルーチンは **1案** を生成し、Notionに `ステータス="下書き"` で書き込む（＝動画プールへ投入）。A案・B案の2案運用は廃止。動画化・音声生成は後段のローカル `make-video` パイプラインが下書きを拾って実行する（ElevenLabs TTS → 動画 → 台帳昇格）。

【重要：このルーチンでは音声生成しない・音声URLも書かない】
音声は後段のローカル make-video が動画生成時に ElevenLabs TTS で都度生成する。**GHA音声フィラーは廃止**。本ルーチンはテキストリライト＋Notion書き込み（下書き）まで。音声URLフィールドには触れない。

【Notion書き込み：クラウドは MCP notion-create-pages を使う】
クラウドサンドボックスには `.env`/`NOTION_TOKEN` が無いため REST は使えない。`notion-create-pages` MCP でデータソース `e8322351-3390-420a-af36-19d6836bee0c` に書く。プロパティのマッピング（プロパティ名・値）は `.claude/skills/sns-rewrite/SKILL.md` §5 を参照。

【自律モード・厳守ルール】
- 質問は一切しない（ask_user_input_v0 を呼ばない）
- 確認も求めない
- エラー時はNotionに `ステータス = "失敗"` を残して終了

【ステップ0：出典フェッチ】Claude Code の WebFetch は .go.jp / .or.jp / news.yahoo.co.jp を直接取得できない。GitHub Actions（`.github/workflows/sources-cache.yml`・毎日 05:45 JST）が事前キャッシュした JSON を WebFetch で取得する：

  https://github.com/yutonn06-cloud/project-milky-way-sirius-shortform-03/releases/download/sources-cache/sources_today.json

4媒体（内閣府／厚労省／Yahoo!ニュース国内／NHK）上位3件・計12候補の配列（各要素 `{source, title, url, pubDate, summary}`）。取得失敗または0件なら Notion に「失敗」を残して終了。

注：FutureTimeline.net は実用的なRSSを公開していないため active feed から除外（`reference/authentic-sources.md` の長期文脈リファレンス扱い）。

【ステップ1】`.claude/skills/sns-rewrite/SKILL.md` 全文 + `workflows/cite_authentic_source.md` を読み、以下のセクションに完全準拠して実行（**すべて1案**）：
- §1 原文選択（直近7日の重複チェックは §「Notion 重複チェック」 のREST query で行う）
- §2 ターゲット選択（軸A・10個から1個）
- §3 文体選択（軸B・5個から1個）
- §3.5 冒頭フック型選択（軸D・6個から1個。直近7本と被る型を避ける）
- §4 リライト実行（1案・300〜400字・敬体厳守）
- §4.5 出典付与（ステップ0で取得した候補から1件。出典行は20〜30字以内）
- §4.7 TikTokキャプション生成（1案・**50字以内**・一人で語るトーン・読者への投げかけ/疑問禁止・「この動画はこういうもの」と分かる説明的な一文。`キャプション` プロパティに格納）
- §5 Notion書き込み（クラウド経路の typed JSON。投稿先 = "ショート動画" 固定、**ステータス = "下書き" 固定**、**`キャプション` を必ず埋める**、音声URL/ファイル名 は書かない、出典URL_A・出典媒体 を必ず埋める）

【ステップ2】最終サマリー（原文タイトル・文字数・出典媒体・NotionページURL）を1〜2行で出力して終了。音声URLについては言及しない。

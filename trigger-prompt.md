クローン済みリポジトリのルート (cwd) で動作してください。本日分のSNSリライト（ショート動画）を1本、自律モードで生成します。

**Single source of truth for rules:**
- `.claude/skills/sns-rewrite/SKILL.md` — 文体・敬体・タメ語禁止・出力フォーマット（**最初に全文読み、これに従う**）
- `workflows/cite_authentic_source.md` — 出典付与の共通SOP
- `reference/authentic-sources.md` — 4本のRSS + 3つの長期文脈リファレンス
- `skill/references/*.md` — 原文集（45ファイル・450本）

トリガープロンプトはオーケストレーションのみを担う。トーン規則は skill ファイルに集約済み。**ここで再記述しない**（重複は drift の温床）。

【重要：このルーチンでは音声生成しない】
ElevenLabs API はサンドボックスのネットワーク許可リストに含まれない。音声生成は毎日 06:15 JST に GitHub Actions（`.github/workflows/audio-filler.yml`）が後から実行する。本ルーチンはテキストリライト＋Notion書き込みまで。

【重要：MCPは使わず Notion REST API を直接叩く】
`Notion:notion-create-pages` などのMCPツールは使用しない。`POST https://api.notion.com/v1/pages`（およびDB query）を直接呼ぶ。リクエスト形式は `.claude/skills/sns-rewrite/SKILL.md` §5 の typed JSON 例を参照。`NOTION_TOKEN` は `.env` または環境変数から取得。

【自律モード・厳守ルール】
- 質問は一切しない（ask_user_input_v0 を呼ばない）
- 確認も求めない
- エラー時はNotionに `ステータス = "失敗"` を残して終了

【ステップ0：出典フェッチ】以下4本のRSSをWebFetchで**並列**取得し、各フィードの上位3件（計12候補）をメモリ上に保持：
- https://www.cao.go.jp/rss/news.rdf  （内閣府）
- https://www.mhlw.go.jp/stf/news.rdf  （厚生労働省）
- https://news.yahoo.co.jp/rss/categories/domestic.xml  （Yahoo!ニュース 国内）
- https://www.nhk.or.jp/rss/news/cat1.xml  （NHKニュース）

サンドボックスでローカルPSスクリプトは動かないため、`tools/fetch-sources.ps1` は使わずWebFetch経路を取る。4本すべて失敗ならNotionに「失敗」を残して終了。

注：FutureTimeline.net は実用的なRSSを公開していないため active feed から除外（`reference/authentic-sources.md` の長期文脈リファレンス扱い）。

【ステップ1】`.claude/skills/sns-rewrite/SKILL.md` 全文 + `workflows/cite_authentic_source.md` を読み、以下のセクションに完全準拠して実行：
- §1 原文選択（直近7日の重複チェックは §「Notion 重複チェック」 のREST query で行う）
- §2 ターゲット選択（軸A・10個から1個）
- §3 文体選択（軸B・5個からA案・B案で異なる2個）
- §4 リライト実行（300〜400字・敬体厳守）
- §4.5 出典付与（ステップ0で取得した15候補からA案・B案で異なる媒体・異なる記事を1件ずつ。出典行は20〜30字以内）
- §5 Notion書き込み（クラウド経路の typed JSON。投稿先 = "ショート動画" 固定、音声URL_A/B は空、出典URL_A・出典URL_B・出典媒体 を必ず埋める）

【ステップ2】最終サマリー（原文タイトル・文字数A/B・出典媒体A/B・NotionページURL）を1〜2行で出力して終了。音声URLについては言及しない。

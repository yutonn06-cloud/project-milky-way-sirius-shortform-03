クローン済みリポジトリのルート (cwd) で動作してください。本日分のX（Twitter）長文リライトを1本、自律モードで生成します。

**Single source of truth for rules:**
- `.claude/skills/sns-rewrite-x/SKILL.md` — 文体・型・テンプレート・固定仕様（**最初に全文読み、これに従う**）
- `workflows/cite_authentic_source.md` — 出典付与の共通SOP
- `reference/authentic-sources.md` — 4本のRSS + 3つの長期文脈リファレンス
- `skill/references/*.md` — 原文集（45ファイル・450本）

トリガープロンプトはオーケストレーションのみを担う。トーン・敬体・タメ語禁止・型の選び方などのルールは上記skillファイルに集約済み。**ここで再記述しない**（重複は drift の温床）。

【重要：MCPは使わず Notion REST API を直接叩く】
`Notion:notion-create-pages` などのMCPツールは使用しない。ローカル実行では:
1. プロパティJSONを `.tmp/props.json` に書く（UTF-8）
2. `powershell -ExecutionPolicy Bypass -File tools\notion-create-page.ps1 -PropertiesFile .tmp\props.json` を呼ぶ
スクリプトがフラットマップから typed JSON へ変換し POST する。`NOTION_TOKEN` は `.env` から自動ロード。

【自律モード・厳守ルール】
- 質問は一切しない（ask_user_input_v0 を呼ばない）
- 確認も求めない。途中で人間に判断を委ねない
- エラー時はNotionに `ステータス = "失敗"` を残して終了

【ステップ0】`powershell -ExecutionPolicy Bypass -File tools\fetch-sources.ps1` を実行（6時間キャッシュなのでヒット時は即終了）。`.tmp/sources_today.json` を読み込み、出典候補15件を確保する。

【ステップ1】`.claude/skills/sns-rewrite-x/SKILL.md` 全文 + `workflows/cite_authentic_source.md` を読み、以下のセクションに完全準拠して実行：
- §1 原文選択（直近7日の重複チェックは §「Notion 重複チェック」 のREST query で行う）
- §2 ターゲット選択（軸A）
- §3 型選択（A型・B型・C型から異なる2つ。B型推奨）
- §4 リライト実行（共通テンプレート8要素・敬体厳守・哲学者引用は実在の人物のみ）
- §4.5 出典付与（`.tmp/sources_today.json` から関連記事をA・B別媒体で1件ずつ）
- §5 Notion書き込み（`tools/notion-create-page.ps1` 経由。投稿先 = "X" 固定、音声URL_A/B は空のまま）

【ステップ2】最終サマリー（原文タイトル・型A/B・文字数A/B・出典媒体A/B・NotionページURL）を1〜2行で出力して終了。

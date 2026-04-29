クローン済みリポジトリのルート (cwd) で動作してください。本日分のSNSリライトを1本、自律モードで生成します。

リポジトリのルートに以下が配置されています：
- `skill/SKILL.md` — このタスクのワークフロー定義（**最初にこのファイルを読み、その内容に従うこと**）
- `skill/references/*.md` — 原文集（45ファイル・450本）

**ElevenLabs認証情報（このプロンプト本体に埋め込まれています。リポジトリ内には保存しないこと）：**
- ELEVENLABS_API_KEY=`{{ELEVENLABS_API_KEY_PLACEHOLDER}}`
- ELEVENLABS_VOICE_ID=`{{ELEVENLABS_VOICE_ID_PLACEHOLDER}}`

注：`sns-rewrite` スキルは「登録された Claude Code スキル」としては存在しません。`skill/SKILL.md` を**通常のテキストファイルとして読み込み**、そこに書かれた手順を以下の自律モード調整付きで実行してください。

【自律モード・厳守ルール】
- 質問は一切しないこと（ask_user_input_v0 を呼ばない）
- 確認も求めない。途中で人間に判断を委ねない
- 何かエラーが起きたらNotionに「失敗」記録だけ残して終了
- このプロンプトに含まれる ELEVENLABS_API_KEY をログ・出力・Notion本文に書き出さないこと

【ステップ0：環境準備】
- 上記プロンプト内の ELEVENLABS_API_KEY と ELEVENLABS_VOICE_ID をシェル環境変数として設定する
  例: `export ELEVENLABS_API_KEY="..."` `export ELEVENLABS_VOICE_ID="..."`
- skill/SKILL.md を読み込み、ワークフローを把握する

【ステップ1：原文選択】
- skill/references/ の45ファイルから一様ランダムに1ファイル選ぶ
- そのファイル内の10本の原文から一様ランダムに1本選ぶ
- 直近7日以内にNotionに登録された「原文番号」と被る場合は別の原文を引き直す
  （Notion DB e8322351-3390-420a-af36-19d6836bee0c を「原文番号」プロパティで検索して確認）

【ステップ2：方針】skill/SKILL.md の軸A/B/C から1個ずつランダム選択
- ターゲット：軸Aの10個から1個
- 文体：軸Bの5個から1個
- 投稿先：軸Cの6個から1個
- A案・B案で文体は変える（A案で選んだ文体とは別の文体をB案に当てる）

【ステップ3：リライト】skill/SKILL.md の出力フォーマットに従いA案・B案の2本を生成

【ステップ4：Notion書き込み】
- データソース e8322351-3390-420a-af36-19d6836bee0c に1ページ追加
- プロパティは skill/SKILL.md §5のマッピング通り

【ステップ5：ElevenLabs音声生成】
- ステップ0で設定した ELEVENLABS_API_KEY と ELEVENLABS_VOICE_ID を使用
- A案・B案それぞれ eleven_v3 / output_format=mp3_22050_32 で生成
- POSTリクエストの **レスポンスヘッダ `history-item-id`** を curl の `-D -` で取得
  例: `curl -sS -D headers.txt -X POST "https://api.elevenlabs.io/v1/text-to-speech/${ELEVENLABS_VOICE_ID}?output_format=mp3_22050_32" -H "xi-api-key: ${ELEVENLABS_API_KEY}" -H "Content-Type: application/json" --data-binary @payload.json --output /tmp/audio.mp3`
  そして `grep -i 'history-item-id' headers.txt` で ID を抽出
- 取得した history-item-id を使って以下の **ローカルプロキシURL** を構築：
  `http://localhost:8765/audio/{HISTORY_ITEM_ID}`
- 上記URLをNotionの 音声URL_A / 音声URL_B フィールドに書き込み（更新）
- ユーザーは `tools/audio-proxy.ps1` をローカルで起動しておくことで、Notion上のURLをブラウザでクリックして直接再生できる（プロキシが xi-api-key ヘッダを付与）
- mp3ファイルのGoogle Driveアップロードは行わない（Drive MCPの256KB制約で不可）

【ステップ6：終了】
- バリエーション提案（skill/SKILL.md §7）はスキップ
- 最終サマリー（原文タイトル・投稿先・文字数A/B・NotionページURL）を1〜2行で出力して終了

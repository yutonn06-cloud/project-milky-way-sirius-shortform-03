# Authentic Sources Reference

権威ある一次ソースのレジストリ。SNSリライトの本文に組み込む出典の選択肢として、すべてのサブスキルがここを参照する。

**消費するスキル：**
- [.claude/skills/sns-rewrite/SKILL.md](../.claude/skills/sns-rewrite/SKILL.md) §4.5
- [.claude/skills/sns-rewrite-x/SKILL.md](../.claude/skills/sns-rewrite-x/SKILL.md) §4.5

**取得経路：**
- ローカル：[tools/fetch-sources.ps1](../tools/fetch-sources.ps1) → `.tmp/sources_today.json`（6時間キャッシュ）
- クラウド：WebFetch で4本のRSSを並列取得

**選定SOP：** [workflows/cite_authentic_source.md](../workflows/cite_authentic_source.md)

---

## アクティブ・フィード（毎回フェッチして引用候補にする）

| # | 媒体名（出典表記） | 種別 | URL | 守備範囲 |
|---|---|---|---|---|
| 1 | 内閣府 | RSS (RDF) | https://www.cao.go.jp/rss/news.rdf | 政府の方針・経済財政・少子化対策・社会保障 |
| 2 | 厚生労働省 | RSS (RDF) | https://www.mhlw.go.jp/stf/news.rdf | 雇用・年金・医療・介護・労働環境 |
| 3 | Yahoo!ニュース（国内） | RSS | https://news.yahoo.co.jp/rss/categories/domestic.xml | 日本国内の社会・話題のニュース |
| 4 | NHKニュース | RSS | https://www.nhk.or.jp/rss/news/cat1.xml | 主要ニュース・報道。記事URLは新ドメイン `news.web.nhk` を返す（`.nhk` ブランドTLD・実在）。 |

**Verified working** as of 2026-05-01. 元々ユーザー提供のURL（`/rss.xml`, `/feed.xml`, `/topics/society.xml` 等）は404だったため、各サイトの実際のフィードパスへ差し替え済み。

## 長期文脈リファレンス（毎回フェッチしないが、テーマ合致時に名前を出す）

| 媒体名 | URL | 用途 |
|---|---|---|
| MIT Technology Review | https://www.technologyreview.com/ | テクノロジーが社会に与える影響、長期的視点 |
| Population Pyramid | https://www.populationpyramid.net/world/2024/ | 人口動態・世代論を語るときの裏付け |
| FutureTimeline | https://www.futuretimeline.net/ | 長期トレンド・人口動態予測（英語）。**RSSは公開されていない**（`/feed.xml` は404、Squarespace `?format=rss` はディレクトリ一覧を返す）。トップページのHTMLから記事タイトルを言及する用途のみ。 |

これらは RSS が公開されていない／静的データのため、`tools/fetch-sources.ps1` は取得しない。引用するときは記事タイトルではなく **媒体名そのもの** を出典として記す（例：`出典：MIT Technology Review』）。

## 出典フォーマット（本文への組み込み）

```
出典：<媒体名>『<記事タイトル>』
```

URLは本文には入れない。Notion の `出典URL_A` / `出典URL_B` プロパティに格納する。詳細は [workflows/cite_authentic_source.md](../workflows/cite_authentic_source.md)。

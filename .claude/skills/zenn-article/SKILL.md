---
name: zenn-article
description: Zennの記事を書くための知識リファレンス。Zennのマークダウン記法、frontmatter、slugの命名規則などの知識を提供する。ユーザーがZenn向けの記事を書く・編集する際に使用する。
disable-model-invocation: false
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Zenn記事リファレンス

Zennプラットフォーム向け記事の記法・フォーマットに関する知識を提供するスキル。

## ファイル構造

```
articles/
└── <slug>.md
```

slugの命名規則:
- 12〜50文字
- 使用可能文字: `a-z`, `0-9`, `-`, `_`

## Frontmatter

```yaml
---
title: "記事タイトル"
emoji: "📝"
type: "tech"
topics: ["topic1", "topic2"]
published: false
---
```

| フィールド | 必須 | 説明 |
|-----------|------|------|
| title | Yes | 記事のタイトル |
| emoji | Yes | カード表示用の絵文字1文字 |
| type | Yes | `tech`（技術記事）or `idea`（アイデア記事） |
| topics | Yes | タグ配列（最大5つ） |
| published | Yes | `true`で公開、`false`で下書き |
| published_at | No | 公開日時 `YYYY-MM-DD` or `YYYY-MM-DD hh:mm`（JST） |

## Zenn Markdown記法

詳細は [references/zenn-markdown.md](references/zenn-markdown.md) を参照。

### 基本記法

- 見出し: `##` 〜 `####`（`#` 見出し1は使わない）
- 太字: `**テキスト**`
- イタリック: `*テキスト*`
- 打ち消し線: `~~テキスト~~`
- インラインコード: `` `code` ``
- リンク: `[テキスト](URL)`
- 画像: `![altテキスト](URL)`
  - 幅指定: `![](URL =250x)`
  - キャプション: 画像の次の行に `*キャプションテキスト*`
- 引用: `> テキスト`
- 区切り線: `-----`
- 脚注: 本文中に`[^1]`、末尾に`[^1]: 脚注内容`

### コードブロック

````markdown
```言語名
コード
```
````

- ファイル名付き: `` ```言語名:ファイル名 ``
- diff表示: `` ```diff 言語名 `` （行頭に `+` `-` `>` `<` ` ` が必要）

### Zenn独自記法

**メッセージボックス:**
```
:::message
通常のメッセージ
:::

:::message alert
警告メッセージ
:::
```

**アコーディオン（トグル）:**
```
:::details タイトル
折りたたみコンテンツ
:::
```

**数式（KaTeX）:**
- ブロック: `$$` で囲む（前後に空行が必要）
- インライン: `$数式$`

**コンテンツ埋め込み:**
- URLカード: URLだけの行、または `@[card](URL)`
- Twitter/X: ポストURLを貼るだけ
- YouTube: 動画URLを貼るだけ
- GitHub: ファイルURLを貼る（`#L1-L3`で行指定可）

### テーブル

```markdown
| ヘッダ1 | ヘッダ2 |
|---------|---------|
| セル1   | セル2   |
```

セル内改行は `<br>` を使用。

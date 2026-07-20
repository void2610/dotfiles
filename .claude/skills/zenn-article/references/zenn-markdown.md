# Zenn Markdown記法 詳細リファレンス

Zennで使えるMarkdown記法の完全リファレンス。SKILL.mdから参照される補足資料。

## 目次

1. [見出し](#見出し)
2. [テキスト装飾](#テキスト装飾)
3. [リスト](#リスト)
4. [リンク](#リンク)
5. [画像](#画像)
6. [コードブロック](#コードブロック)
7. [テーブル](#テーブル)
8. [引用](#引用)
9. [脚注](#脚注)
10. [区切り線](#区切り線)
11. [数式（KaTeX）](#数式katex)
12. [メッセージ](#メッセージ)
13. [アコーディオン](#アコーディオン)
14. [ネスト記法](#ネスト記法)
15. [コンテンツ埋め込み](#コンテンツ埋め込み)
16. [HTMLコメント](#htmlコメント)

---

## 見出し

`#` から `####` まで使用可能。アクセシビリティの観点から**見出し2（`##`）から始める**ことを推奨。

```markdown
## 見出し2
### 見出し3
#### 見出し4
```

## テキスト装飾

```markdown
*イタリック*
**太字**
~~打ち消し線~~
`インラインコード`
```

## リスト

### 箇条書き
```markdown
- アイテム1
- アイテム2
  - ネストしたアイテム
```

`*` でも可。

### 番号付きリスト
```markdown
1. 最初
2. 次
3. 最後
```

## リンク

```markdown
[アンカーテキスト](URL)
```

エディタではテキスト選択後にURLをペーストするとリンクが自動生成される。

## 画像

### 基本
```markdown
![altテキスト](画像URL)
```

### 横幅指定（px単位）
```markdown
![](画像URL =250x)
```

`=幅x` の形式。高さは自動調整。

### キャプション
画像のすぐ下の行にイタリックで記述:
```markdown
![](画像URL)
*これはキャプションです*
```

### リンク付き画像
```markdown
[![altテキスト](画像URL)](リンク先URL)
```

## コードブロック

### 基本（言語指定でシンタックスハイライト）

````markdown
```javascript
const hello = "world";
```
````

シンタックスハイライトにはShikiが使用されている。

### ファイル名表示

````markdown
```javascript:src/index.js
const hello = "world";
```
````

コロン区切りで `言語:ファイル名` を指定。

### diff表示

````markdown
```diff javascript
+ const added = true;
- const removed = false;
> const modified = "new";
< const modified = "old";
  const unchanged = "same";
```
````

`diff 言語名` で両方を適用。各行の先頭に `+`、`-`、`>`、`<`、` `（スペース）のいずれかが必要。

## テーブル

```markdown
| ヘッダ1 | ヘッダ2 | ヘッダ3 |
|---------|---------|---------|
| セル1   | セル2   | セル3   |
| セル4   | セル5   | セル6   |
```

セル内で改行するには `<br>` を使う:

```markdown
| ヘッダ | 内容 |
|--------|------|
| セル   | 1行目<br>2行目 |
```

## 引用

```markdown
> 引用テキスト
> 複数行の引用
```

## 脚注

本文中:
```markdown
テキスト[^1]とテキスト[^2]
```

記事末尾:
```markdown
[^1]: 脚注の内容1
[^2]: 脚注の内容2
```

## 区切り線

```markdown
-----
```

ハイフン5つ以上。

## 数式（KaTeX）

### ブロック数式
前後に**空行が必要**:

```markdown
テキスト

$$
e^{i\pi} + 1 = 0
$$

テキスト
```

### インライン数式
```markdown
$a \ne 0$ のとき、$ax^2 + bx + c = 0$ の解は...
```

## メッセージ

### 通常メッセージ
```markdown
:::message
これは通常のメッセージです。補足情報や注意事項に使います。
:::
```

### 警告メッセージ
```markdown
:::message alert
これは警告メッセージです。重要な注意事項に使います。
:::
```

## アコーディオン

```markdown
:::details タイトル
ここに折りたたまれるコンテンツを書く。
長いコード例や補足情報に便利。
:::
```

## ネスト記法

外側のコンテナに `:` を追加することでネスト可能:

```markdown
::::details 外側のアコーディオン
:::message
ネストされたメッセージ
:::
::::
```

## コンテンツ埋め込み

### URLカード
URLだけの行で自動的にカードに変換:
```markdown
https://example.com
```

または明示的に:
```markdown
@[card](https://example.com)
```

### Twitter/X
ポストのURLを貼るだけで埋め込み:
```markdown
https://twitter.com/username/status/1234567890
```

リプライ元を非表示にする場合:
```markdown
https://twitter.com/username/status/1234567890?conversation=none
```

### YouTube
動画URLを貼るだけ:
```markdown
https://www.youtube.com/watch?v=XXXXXXXXXXX
```

### GitHub
ファイルURLを貼る。行指定も可能:
```markdown
https://github.com/owner/repo/blob/main/src/index.ts#L1-L10
```

### その他の埋め込み対応サービス
- CodePen
- Figma
- StackBlitz
- SpeakerDeck

## HTMLコメント

```markdown
<!-- コメント（表示されない） -->
```

複数行コメントは非対応。

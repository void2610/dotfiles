---
name: discord-image
description: Discord webhook 経由で個人チャンネルに画像を送信するスキル。リモートコントロール中の Claude がユーザーに画面状態や成果物画像を共有する用途。トリガー「画像を Discord に送って」「スクリーンショット送って」「画面を共有して」「send screenshot to discord」等のユーザー指示、または `discord-image` スキル指定。ローカルファイル / macOS スクリーンショット / 画像 URL の 3 モードに対応。
---

# discord-image

Discord webhook を使って個人チャンネルに画像を送信する。リモート作業中、ユーザーが手元で画面を直接確認できない状況で Claude から画像を届ける用途。

実処理は同梱の `send.sh` に集約されている。Claude はモードと引数を判断して `send.sh` を呼び出すだけでよい。

## 呼び出し方

スクリプトの絶対パス:

```
~/.claude/skills/discord-image/send.sh
```

### モード 1: ローカルファイル送信

Claude が生成・編集した既存画像ファイルを送る。

```bash
~/.claude/skills/discord-image/send.sh file <画像パス> [メッセージ]
```

例:
```bash
~/.claude/skills/discord-image/send.sh file /tmp/output.png "生成した図です"
```

### モード 2: macOS スクリーンショットを撮って送信

`screencapture` で撮影してからアップロードする。リモート画面確認の主用途。

```bash
~/.claude/skills/discord-image/send.sh screenshot [メッセージ] [-- <screencapture追加オプション>]
```

例:
```bash
# 画面全体
~/.claude/skills/discord-image/send.sh screenshot "現在の画面"

# 領域指定 (x,y,w,h)
~/.claude/skills/discord-image/send.sh screenshot "ターミナル領域" -- -R100,100,800,600

# 特定ディスプレイ
~/.claude/skills/discord-image/send.sh screenshot -- -D2
```

### モード 3: 画像 URL を embed で送信

ファイルアップロード無しで Discord 上に embed カードとして埋め込み表示する。

```bash
~/.claude/skills/discord-image/send.sh url <画像URL> [説明]
```

例:
```bash
~/.claude/skills/discord-image/send.sh url "https://example.com/foo.png" "参考画像"
```

## エラー対応

- `webhook URL ファイルが見つかりません`: 上記セットアップ手順を案内
- `curl: (22) ... 401/404`: webhook URL が失効・削除されている可能性。ユーザーに再発行を依頼
- `8MB 上限を超える可能性があります` 警告 + curl 失敗: `sips -Z 1920 <file>` で縮小、または `sips -s format jpeg -s formatOptions 60 <file> --out <out>.jpg` で再エンコードして再送

## 注意事項

- webhook URL の中身を会話やログに出さない。スクリプトは内部で `cat` するだけで標準出力には流さない設計。
- スクリーンショットの一時ファイルはスクリプト内で `trap` により自動削除される。

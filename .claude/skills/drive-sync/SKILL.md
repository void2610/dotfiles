---
name: drive-sync
description: チームメンバーが Google Drive 共有フォルダに置いたゲーム素材を rclone で ~/Documents/rclone/<repo> へ一方向同期するスキル。トリガー「素材を最新にして」「Drive の素材を同期して」「Drive にある素材を見て」「drive sync」等のユーザー指示、または Drive 素材を参照する必要があるタスクの着手前。
---

# drive-sync

Google Drive 共有フォルダ → `~/Documents/rclone/<repo>` の**一方向**ミラー。rclone 操作はすべて `scripts/sync.sh` に集約されている。

## 絶対ルール

- rclone を直接呼ばない。必ず `sync.sh` を経由する (同期方向・除外・削除上限を固定するため)
- Drive へ書き込む操作 (`copy`/`sync` の逆向き、`delete`、`mkdir` 等) は行わない。remote は `drive.readonly` スコープで作成しているので、書き込みは失敗するのが正常
- `~/Documents/rclone/<repo>` 内のファイルは編集しない。次回の同期で上書き・削除される

## コマンド

`<repo>` は省略するとカレントの git リポジトリ名になる。

```bash
~/.claude/skills/drive-sync/scripts/sync.sh status [repo]  # 差分確認 (dry-run)
~/.claude/skills/drive-sync/scripts/sync.sh pull [repo]    # 同期 + md の埋め込み画像切り出し
~/.claude/skills/drive-sync/scripts/sync.sh ls [repo]      # Drive 側のファイル一覧
~/.claude/skills/drive-sync/scripts/sync.sh list           # 登録済みプロジェクト一覧
```

素材を参照するタスクでは、まず `status` を実行し、差分があれば `pull` してから読む。

## 同期結果の読み方

- Google ドキュメントは `.md`、スプレッドシートは `.csv`、スライドは `.pdf` でエクスポートされる
- md の埋め込み画像は `<ドキュメント名>.images/imageN.png` に切り出され、本文の参照はそのパスに書き換わっている。画像の中身が必要なら Read で開く
- スプレッドシートの csv は**先頭シートのみ**。他のシートが必要ならユーザーに伝える
- psd / blend / 音声などはファイル名・サイズ以上の情報は得られない

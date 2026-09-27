---
name: drive-sync
description: チームメンバーが Google Drive 共有フォルダに置いたゲーム素材を rclone で ~/Documents/rclone/<repo> へ一方向同期するスキル。トリガー「素材を最新にして」「Drive の素材を同期して」「Drive にある素材を見て」「drive sync」等のユーザー指示、または Drive 素材を参照する必要があるタスクの着手前。プロジェクト設定の追加 (フォルダ ID・除外設定) もこのスキルで行う。
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

## 設定 (dotfiles で一元管理)

| ファイル | 内容 |
|---|---|
| `~/.config/drive-sync/projects.conf` | `<repo> <folder_id>` の対応表 |
| `~/.config/drive-sync/filters/_common.filter` | 全プロジェクト共通の除外 |
| `~/.config/drive-sync/filters/<repo>.filter` | プロジェクト固有の除外 (任意) |

実体は `~/dotfiles/.config/drive-sync/`。フォルダ ID は `drive.google.com/drive/folders/<ID>` の部分。

### プロジェクトを追加する手順

1. `projects.conf` に `<repo> <folder_id>` を追記
2. ビルドデータ等を除外するなら `filters/<repo>.filter` を作成 (書式: `- /Build/**`。先頭 `/` は同期ルート直下に固定)
3. `sync.sh ls <repo>` で Drive 側が見えること、除外対象が出ないことを確認 (`ls` はフィルタ非適用なので `status` でも確認)
4. `sync.sh pull <repo>`

各リポジトリ側のファイル (`.claude/settings.local.json` 等) は変更しない。設定は dotfiles に一元管理する。

除外を後から追加しても、同期済みのファイルはローカルに残る (`*.images/` を守るため `--delete-excluded` を使っていない)。不要なら手動で削除する。

## 初回セットアップ (マシンごとに 1 回)

rclone は nix-config の Homebrew (`commonBrews`) で入る。remote `gdrive` は OAuth のブラウザ認証が要るため、ユーザーに実行してもらう:

```bash
rclone config create gdrive drive scope=drive.readonly client_id=<ID> client_secret=<SECRET>
```

- client_id / secret は Google Cloud Console で発行した自分用のもの (rclone 共有の ID はレート制限に当たりやすい)
- `~/.config/rclone/` は OAuth トークンを含むため dotfiles の `.gitignore` で除外済み

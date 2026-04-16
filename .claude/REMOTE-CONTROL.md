# Claude Code リモートコントロール運用ガイド

ntfy.sh 経由で Claude Code の `remote-control` をヘッドレス起動し、
claude.ai/code（Web / スマホアプリ）から操作する仕組みの運用知見。

## アーキテクチャ

```
スマホ / ブラウザ
  │  ntfy.sh (void2610-cmd)
  ▼
claude-remote-listener.sh  ← launchd 常駐 (KeepAlive)
  │  メッセージ受信 → JSON パース
  ▼
claude remote-control      ← プロジェクトディレクトリで起動
  │  bridge URL 発行
  ▼
claude.ai/code アプリに表示 → セッション操作
```

## 起動方法

ntfy.sh にメッセージを送信:

```bash
# 起動
curl -d '{"dir":"~/Documents/GitHub/my-project"}' https://ntfy.sh/void2610-cmd

# 停止（全インスタンス）
curl -d "stop" https://ntfy.sh/void2610-cmd-stop
```

## 既知の問題と対処法

### 1. セッションがアプリに表示されない

**原因**: `--no-create-session-in-dir` を使うと初期セッションが作成されず、アプリ側のリストに表示されない。

**対処**: `--no-create-session-in-dir` は使わない。初期セッション作成が必須。

### 2. セッション作成 API 400 エラー (`source: Extra inputs are not permitted`)

**原因**: `~/.claude/projects/` 配下の古いセッションデータが、現在の API と互換性のないフィールドを送信している。

**対処**: 該当プロジェクトのセッションデータを退避・削除する。

```bash
# 問題のプロジェクトのセッションデータを退避
mv ~/.claude/projects/-Users-shuya-Documents-GitHub-<project-name> \
   ~/.claude/projects/-Users-shuya-Documents-GitHub-<project-name>.backup
```

退避後に `remote-control` を再起動すれば新しいセッションデータが作られる。

### 3. `--permission-mode bypassPermissions` がセッション作成 API で拒否される

**原因**: CLI v2.1.85 時点で、`--permission-mode` フィールドがセッション作成 API に渡されると
`permission_mode: Extra inputs are not permitted` エラーになることがある。

**対処**: 現在はリスナーから `--permission-mode` を外している。
代わりに `~/.claude/settings.json` で広範なパーミッションを設定:

```json
{
  "permissions": {
    "allow": ["Bash(*)", "Edit", "Write", "Read", "Glob", "Grep", "WebSearch", "WebFetch", "mcp__*"],
    "defaultMode": "bypassPermissions"
  }
}
```

### 4. 数時間放置でセッションが死ぬ (`Session failed: Process exited with error`)

**原因**: セッションが約 4 時間で死亡する。Claude Code 側の WebSocket 接続タイムアウトまたはトークン期限切れと推測。

**対処**: リスナーに 5 分間隔のヘルスチェックループを追加済み。
プロセス死亡を検知すると同じディレクトリで自動再起動する。

ただし、**認証トークン切れ** (401) の場合は自動復旧できない。
対話的に `claude /login` を実行する必要がある。

### 5. GitHub Organization リポジトリが表示されない

**原因**: claude.ai/code の GitHub 連携で、Organization（例: `void2610-org`）へのアクセスが許可されていない。

**対処**: claude.ai の設定 → GitHub 連携で該当 Organization を認可する。

## デバッグ方法

```bash
# デバッグログ付きで手動起動
cd /path/to/project
claude remote-control --debug-file /tmp/rc-debug.log

# リスナーログ確認
tail -f ~/.claude/remote-logs/listener.log

# セッションログ確認（タイムスタンプ付き）
ls -lt ~/.claude/remote-logs/*.log | head

# 実行中プロセスとディレクトリの確認
pgrep -f "claude remote-control" | while read pid; do
  dir=$(lsof -p $pid 2>/dev/null | grep cwd | awk '{print $NF}')
  echo "PID=$pid dir=$dir"
done
```

## ファイル構成

| ファイル | 説明 |
|---------|------|
| `~/.claude/claude-remote-listener.sh` | ntfy.sh リスナー本体 |
| `~/.claude/notify.sh` | ntfy.sh 通知送信スクリプト (hooks 用) |
| `~/.claude/settings.json` | グローバル設定（パーミッション、hooks） |
| `~/.claude/remote-logs/listener.log` | リスナーログ |
| `~/.claude/remote-logs/<timestamp>.log` | 各セッションログ |
| `~/nix-config/home-manager/profiles/server.nix` | launchd エージェント定義 |

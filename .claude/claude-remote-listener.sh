#!/bin/bash

# ntfy.sh経由でClaude Codeのリモートコントロールを起動するリスナースクリプト
# 使い方: スマホのntfy.shアプリから void2610-cmd トピックにJSONを送信
# 例: {"dir":"~/projects/my-app"}
# 例: {"dir":"~/projects/my-app","name":"my-app作業"}

set -euo pipefail

NTFY_CMD_TOPIC="https://ntfy.sh/void2610-cmd/json"
LOG_DIR="${HOME}/.claude/remote-logs"
CLAUDE_BIN="$(command -v claude)"
JQ_BIN="$(command -v jq)"

mkdir -p "$LOG_DIR"

# ログ出力
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/listener.log"
}

# 受信メッセージを処理
process_message() {
    local body="$1"
    local dir name

    # JSONパース
    dir=$("$JQ_BIN" -r '.dir // empty' <<< "$body")
    name=$("$JQ_BIN" -r '.name // empty' <<< "$body")

    # チルダ展開
    dir="${dir/#\~/$HOME}"

    # バリデーション
    if [ -z "$dir" ]; then
        log "エラー: dirは必須です (受信: $body)"
        return 1
    fi
    if [ ! -d "$dir" ]; then
        log "エラー: ディレクトリが存在しません: $dir"
        return 1
    fi

    # claude remote-control の引数を構築
    local cmd_args=(remote-control)
    if [ -n "$name" ]; then
        cmd_args+=(--name "$name")
    fi

    log "リモートコントロール起動: dir=$dir name=${name:-auto}"

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$LOG_DIR/${timestamp}.log"

    # Claude リモートコントロール起動（バックグラウンドで実行し続ける）
    (cd "$dir" && "$CLAUDE_BIN" "${cmd_args[@]}") >> "$log_file" 2>&1 &
    log "リモートコントロール起動完了 (PID=$!): $log_file"
}

# メインループ: ntfy.shのJSONストリームを購読
log "リスナー開始"

while true; do
    curl -sN "$NTFY_CMD_TOPIC" --connect-timeout 30 | while IFS= read -r line; do
        # ntfy.shのJSONストリームからmessageイベントのみ処理
        event=$("$JQ_BIN" -r '.event // empty' <<< "$line" 2>/dev/null) || continue
        if [ "$event" = "message" ]; then
            msg_body=$("$JQ_BIN" -r '.message // empty' <<< "$line")
            if [ -n "$msg_body" ]; then
                log "メッセージ受信: $msg_body"
                process_message "$msg_body"
            fi
        fi
    done

    # 接続切断時は5秒待って再接続
    log "接続切断。5秒後に再接続..."
    sleep 5
done

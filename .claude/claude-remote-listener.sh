#!/bin/bash

# ntfy.sh経由でClaude Codeのリモートコントロールを起動・停止するリスナースクリプト
# 起動: void2610-cmd トピックに {"dir":"~/projects/my-app"} を送信
# 停止: void2610-cmd-stop トピックに任意のメッセージを送信（全インスタンス終了）

set -u

NTFY_CMD_TOPIC="https://ntfy.sh/void2610-cmd/json"
NTFY_STOP_TOPIC="https://ntfy.sh/void2610-cmd-stop/json"
LOG_DIR="${HOME}/.claude/remote-logs"
CLAUDE_BIN="$(command -v claude || echo "")"
JQ_BIN="$(command -v jq || echo "")"

if [ -z "$CLAUDE_BIN" ] || [ -z "$JQ_BIN" ]; then
    echo "エラー: claude または jq が見つかりません (claude=$CLAUDE_BIN, jq=$JQ_BIN)" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

# ログ出力
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/listener.log"
}

# 起動中の全 remote-control インスタンスを終了する
stop_all() {
    local pids
    pids=$(pgrep -f "claude remote-control" 2>/dev/null || true)
    if [ -z "$pids" ]; then
        log "停止: 実行中のインスタンスなし"
        return
    fi
    echo "$pids" | xargs kill 2>/dev/null || true
    log "停止: PID=$pids を終了しました"
}

# 受信メッセージを処理
process_message() {
    local body="$1"
    local dir name

    # JSONパース
    dir=$("$JQ_BIN" -r '.dir // empty' <<< "$body" 2>/dev/null) || true
    name=$("$JQ_BIN" -r '.name // empty' <<< "$body" 2>/dev/null) || true

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
    local cmd_args=(remote-control --permission-mode bypassPermissions)
    if [ -n "$name" ]; then
        cmd_args+=(--name "$name")
    fi

    log "リモートコントロール起動: dir=$dir name=${name:-auto}"

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$LOG_DIR/${timestamp}.log"

    # Claude リモートコントロール起動（全許可モード・バックグラウンドで実行し続ける）
    (cd "$dir" && "$CLAUDE_BIN" "${cmd_args[@]}") >> "$log_file" 2>&1 &
    log "リモートコントロール起動完了 (PID=$!): $log_file"
}

# 停止トピックを別プロセスで購読
subscribe_stop() {
    while true; do
        curl -sfN "$NTFY_STOP_TOPIC" --connect-timeout 30 --max-time 0 2>/dev/null | while IFS= read -r line; do
            [ -z "$line" ] && continue
            event=$("$JQ_BIN" -r '.event // empty' <<< "$line" 2>/dev/null) || continue
            if [ "$event" = "message" ]; then
                log "停止メッセージ受信"
                stop_all
            fi
        done
        log "停止トピック接続切断。10秒後に再接続..."
        sleep 10
    done
}

# メインループ: ntfy.shのJSONストリームを購読
log "リスナー開始"

# 停止トピックの購読をバックグラウンドで起動
subscribe_stop &

while true; do
    curl -sfN "$NTFY_CMD_TOPIC" --connect-timeout 30 --max-time 0 2>/dev/null | while IFS= read -r line; do
        # 空行（keepalive）をスキップ
        [ -z "$line" ] && continue
        # ntfy.shのJSONストリームからmessageイベントのみ処理
        event=$("$JQ_BIN" -r '.event // empty' <<< "$line" 2>/dev/null) || continue
        if [ "$event" = "message" ]; then
            msg_body=$("$JQ_BIN" -r '.message // empty' <<< "$line" 2>/dev/null) || continue
            if [ -n "$msg_body" ]; then
                log "メッセージ受信: $msg_body"
                process_message "$msg_body" || log "エラー: メッセージ処理に失敗: $msg_body"
            fi
        fi
    done

    # 接続切断時は10秒待って再接続
    log "接続切断。10秒後に再接続..."
    sleep 10
done

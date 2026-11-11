#!/bin/bash

# Claude Code通知スクリプト
# 使用例: ./notify.sh "Stop" "成功"

EVENT_TYPE="$1"
STATUS="$2"

case "$EVENT_TYPE" in
    "Stop")
        case "$STATUS" in
            "success")
                MESSAGE="✅ タスク完了"
                ;;
            "error")
                MESSAGE="❌ エラーが発生しました"
                ;;
            "warning")
                MESSAGE="⚠️ 警告あり"
                ;;
            "build")
                MESSAGE="🔨 ビルド完了"
                ;;
            "test")
                MESSAGE="🧪 テスト完了"
                ;;
            *)
                MESSAGE="🔄 タスク終了"
                ;;
        esac
        ;;
    "Notification")
        # 入力待ちなど許可以外の通知も同じ hook に来るので、標準入力の notification_type で分ける
        INPUT=$(cat)
        case "$(echo "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)" in
            "permission_prompt")
                MESSAGE="⏳ 許可待機中..."
                ;;
            "idle_prompt")
                MESSAGE="💬 入力待ち"
                ;;
            *)
                MESSAGE="🔔 $(echo "$INPUT" | jq -r '.message // "Claude Code通知"' 2>/dev/null)"
                ;;
        esac
        ;;
    *)
        MESSAGE="📱 Claude Code通知"
        ;;
esac

curl -H "Title: Claude Code" -d "$MESSAGE" ntfy.sh/void2610
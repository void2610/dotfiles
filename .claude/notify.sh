#!/bin/bash

# Claude Code通知スクリプト
# 使用例: ./notify.sh "Stop" "成功" / ./notify.sh "Autopilot" "<本文>"

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
        MESSAGE="⏳ 許可待機中..."
        ;;
    "Autopilot")
        MESSAGE="🤖 autopilot: $STATUS"
        ;;
    *)
        MESSAGE="📱 Claude Code通知"
        ;;
esac

curl -H "Title: Claude Code" -d "$MESSAGE" ntfy.sh/void2610
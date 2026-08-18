#!/bin/bash
# Manual (default) モード時のみ全ツールを確認制にし、allow ルールを実質無効化する
input=$(cat)
mode=$(echo "$input" | jq -r '.permission_mode')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# statusline がモードバッジを表示できるよう、現在のモードをセッション別ファイルへ書き出す
if [ -n "$session_id" ]; then
  echo "$mode" > "${TMPDIR:-/tmp}/claude-pmode-${session_id}" 2>/dev/null
fi

if [ "$mode" = "default" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "Manual mode: 全操作を確認制にしています"
    }
  }'
fi
exit 0

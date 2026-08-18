#!/bin/bash
# Manual (default) モード時のみ全ツールを確認制にし、allow ルールを実質無効化する
mode=$(jq -r '.permission_mode')

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

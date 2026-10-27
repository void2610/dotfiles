#!/bin/bash
# bypass モードでもプロジェクトの ask ルールは確認を出すため、確認直前に許可を返して全操作を通す
input=$(cat)
mode=$(echo "$input" | jq -r '.permission_mode')

if [ "$mode" = "bypassPermissions" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
fi
exit 0

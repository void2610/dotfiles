#!/usr/bin/env bash
# git commit / git push / gh pr create の直叩きを禁止し、対応スキル経由の実行を強制する PreToolUse hook。
# 各スキル (commit / pr-create / pr-review-fix) は実際のコマンドに CLAUDE_GIT_SKILL=<skill> を前置する規約になっている。
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")

if grep -qE '\b(git[[:space:]]+commit|git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create)\b' <<<"$command"; then
  if ! grep -qE 'CLAUDE_GIT_SKILL=(commit|pr-create|pr-review-fix|branch-create)\b' <<<"$command"; then
    echo "git commit / git push / gh pr create の直接実行はブロックされました。commit / pr-create / pr-review-fix スキル経由で (CLAUDE_GIT_SKILL=<skill名> を前置して) 実行してください。" >&2
    exit 2
  fi
fi

exit 0

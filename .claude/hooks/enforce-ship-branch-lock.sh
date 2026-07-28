#!/usr/bin/env bash
# ship フロー中のブランチ作成・移動を禁止する PreToolUse hook (状態判定は ship.sh guard に委譲)。
set -uo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# 対象: git switch / git checkout / git worktree add (git -C <dir> 形式も含む)
grep -qE '\bgit([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(switch|checkout|worktree[[:space:]]+add)\b' <<<"$command" || exit 0
# "git checkout -- <path>" のファイル復元はブランチ移動ではないため許可
grep -qE '\bgit([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+--([[:space:]]|$)' <<<"$command" && exit 0

ship="$HOME/.claude/skills/ship/scripts/ship.sh"
[[ -x "$ship" && -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# exit 3 のみがロック検知 (guard 自体の失敗で誤ブロックしない)
msg=$("$ship" guard 2>&1); rc=$?
if [[ $rc -eq 3 ]]; then
  echo "ブランチ操作をブロック: $msg" >&2
  exit 2
fi
exit 0

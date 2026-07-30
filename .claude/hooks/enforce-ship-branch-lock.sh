#!/usr/bin/env bash
# 作業中 (ship フロー進行中 or 現在ブランチに open PR) のブランチ作成・移動を禁止する PreToolUse hook。
set -uo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# 対象: git switch / git checkout / git worktree add (git -C <dir> 形式も含む)
grep -qE '\bgit([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(switch|checkout|worktree[[:space:]]+add)\b' <<<"$command" || exit 0
# "git checkout -- <path>" のファイル復元はブランチ移動ではないため許可
grep -qE '\bgit([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+--([[:space:]]|$)' <<<"$command" && exit 0

ship="$HOME/.claude/skills/ship/scripts/ship.sh"
[[ -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# (1) ship フローのロック。exit 3 のみがロック検知 (guard 自体の失敗で誤ブロックしない)。ship ロックは絶対 (escape 不可)。
if [[ -x "$ship" ]]; then
  msg=$("$ship" guard 2>&1); rc=$?
  if [[ $rc -eq 3 ]]; then
    echo "ブランチ操作をブロック: $msg" >&2
    exit 2
  fi
fi

# (2) ship 未 init でも open PR があれば禁止。ユーザーが明示承認したら 'SHIP_ALLOW_BRANCH_SWITCH=1 <同じコマンド>' で再実行 (監査可能な escape)。
grep -qE '(^|[^A-Za-z0-9_])SHIP_ALLOW_BRANCH_SWITCH=1' <<<"$command" && exit 0
command -v gh >/dev/null 2>&1 || exit 0
default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[[ -n "$cur" && -n "$default" && "$cur" != "$default" ]] || exit 0
prstate=$(gh pr view --json state --jq .state 2>/dev/null || true)
if [[ "$prstate" == "OPEN" ]]; then
  echo "ブランチ操作をブロック: 現在ブランチ '$cur' には OPEN な PR があります (フロー進行中)。作業中のブランチ切り替え・新規作成は禁止です。別ブランチが必要ならユーザーに報告し指示を待つこと。ユーザーが明示的に承認した場合のみ、同じコマンドを 'SHIP_ALLOW_BRANCH_SWITCH=1 <cmd>' の形で再実行すること。" >&2
  exit 2
fi
exit 0

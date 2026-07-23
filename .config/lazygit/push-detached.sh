#!/usr/bin/env bash
# push を新セッションへ切り離して実行し、lazygit(nvim float) を閉じても中断されないようにする。第1引数で push モード (normal|lease|force) を受け取り、upstream 未設定なら -u origin HEAD で設定する。
set -eu

self="$HOME/.config/lazygit/push-detached.sh"
detach="$HOME/.config/lazygit/run-detached.sh"

if [ "${1:-}" = "--worker" ]; then
  mode="${2:-normal}"
  notify() { terminal-notifier -title "lazygit push" -message "$1" >/dev/null 2>&1 || true; }

  branch=$(git rev-parse --abbrev-ref HEAD)
  # upstream 未設定のブランチは初回 push で追跡設定する。
  if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    set -- push
  else
    set -- push -u origin HEAD
  fi
  case "$mode" in
    lease) set -- "$@" --force-with-lease ;;
    force) set -- "$@" --force ;;
  esac

  if git "$@" >/dev/null 2>&1; then
    notify "push 完了 (${mode}): $branch"
  else
    notify "push 失敗 (${mode}): $branch"
    exit 1
  fi
  exit 0
fi

mode="${1:-normal}"
exec "$detach" "$self" --worker "$mode"

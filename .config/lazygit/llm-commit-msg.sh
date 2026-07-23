#!/usr/bin/env bash
# ステージ済み diff から claude で1行コミットメッセージを生成しコミットする。生成〜コミットを新セッションへ切り離すため lazygit(nvim float) を閉じても完走する。
set -eu

self="$HOME/.config/lazygit/llm-commit-msg.sh"
detach="$HOME/.config/lazygit/run-detached.sh"

if [ "${1:-}" = "--worker" ]; then
  notify() { terminal-notifier -title "lazygit commit" -message "$1" >/dev/null 2>&1 || true; }

  diff=$(git diff --cached)
  # 許可する type prefix のホワイトリスト。ここに無いものは弾く
  allowed_types='feat|fix|refac|docs|chore|style|test'
  prompt="Write a concise one-line git commit message summarizing the staged changes. Follow the Conventional Commits format with one of these exact English type prefixes (do not use any other prefix, do not spell them out): ${allowed_types}. Do NOT include a scope in parentheses. The prefix may be followed by an optional '!' for breaking changes, then ': ' and the description. Write the description in Japanese. Output only the message text, no surrounding quotes or explanation."

  # claude が前置き/引用符/ホワイトリスト外 prefix を返す場合に備え、妥当な形式になるまで最大3回試行する。
  max_attempts=3
  attempt=1
  msg=""
  validation_regex="^(${allowed_types})!?: .+"
  while [ "$attempt" -le "$max_attempts" ]; do
    candidate=$(printf '%s' "$diff" | claude -p --model haiku "$prompt" | head -n1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if printf '%s' "$candidate" | grep -Eq "$validation_regex"; then
      msg="$candidate"
      break
    fi
    attempt=$((attempt + 1))
  done

  if [ -z "$msg" ]; then
    notify "コミットメッセージの生成に失敗しました。"
    exit 1
  fi
  if git commit -m "$msg" >/dev/null 2>&1; then
    notify "コミットしました: $msg"
  else
    notify "コミットに失敗しました: $msg"
    exit 1
  fi
  exit 0
fi

# lazygit が同期的に呼ぶ入口。空コミット回避の軽いチェックだけ即時に行い lazygit にエラー表示させる。
if git diff --cached --quiet; then
  echo 'ステージ済みの変更がありません。' >&2
  exit 1
fi

# 生成〜コミットを detach する。cancel-job.sh から中止できるよう repo 単位のジョブ ID を渡す。
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
export LG_JOB_ID="commit-$(printf '%s' "$top" | shasum | cut -c1-12)"
exec "$detach" "$self" --worker

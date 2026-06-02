#!/usr/bin/env bash
# ステージ済み diff から claude で1行コミットメッセージを生成し、そのままコミットするスクリプト。
# lazygit の customCommand から output=log + loadingText 付きで呼ばれ、
# 別ウィンドウ（terminal サブプロセスや nvim）を出さずに lazygit 内で完結させる。
# 生成メッセージを編集したい場合は、コミット後に lazygit の `r`（reword）で直す。
set -eu

# ステージ済みの変更が無ければコミットしない。
if git diff --cached --quiet; then
  echo 'ステージ済みの変更がありません。' >&2
  exit 1
fi

# diff を一度だけ取得し、再試行で使い回す。
diff=$(git diff --cached)
prompt='Write a concise one-line git commit message summarizing the staged changes. Follow the Conventional Commits format with an English type prefix (feat:, fix:, refactor:, docs:, chore:, etc.) but write the description in Japanese. Output only the message text, no surrounding quotes or explanation.'

# Conventional Commits 形式（type[scope][!]: 本文）を満たすまで最大3回試行する。
# claude が前置きや引用符を付けて返した場合などをバリデーションで弾く。
max_attempts=3
attempt=1
msg=""
while [ "$attempt" -le "$max_attempts" ]; do
  # 1行目を取得し、前後の空白を除去する。
  candidate=$(printf '%s' "$diff" | claude -p "$prompt" | head -n1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # 簡易バリデーション: 「type: 本文」形式か（feat:, fix(scope):, refactor!: など）。
  if printf '%s' "$candidate" | grep -Eq '^[a-z]+(\([^)]+\))?!?: .+'; then
    msg="$candidate"
    break
  fi
  echo "生成結果が Conventional Commits 形式ではないため再試行します（$attempt/$max_attempts）: $candidate" >&2
  attempt=$((attempt + 1))
done

# 3回試しても妥当なメッセージが得られなければコミットせず終了する。
if [ -z "$msg" ]; then
  echo 'コミットメッセージの生成に失敗しました。' >&2
  exit 1
fi

git commit -m "$msg"

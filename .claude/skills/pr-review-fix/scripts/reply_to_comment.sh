#!/usr/bin/env bash
# 指定したレビューコメントに対して、固定フォーマットで返信する。
#
# スクリプトが末尾に必ず Claude Code 署名行を付加するので、
# 呼び出し側は本文 (日本語 1 文) だけ渡せばよい。
#
# 使い方:
#   ./reply_to_comment.sh <comment_id> <body> [pr_number]
#
# 引数:
#   comment_id : レビューコメントの databaseId
#   body       : 日本語 1 文。以下の 2 パターンのみ使う。
#                A) コード修正の返信:
#                     "<FULL_SHA> で修正しました。"
#                   FULL_SHA は 40 文字の完全 SHA (バッククォート無し)。
#                   GitHub UI が自動でコミットリンクに整形する。
#                   複数コミットに跨る場合は読点区切りで列挙:
#                     "<SHA1>、<SHA2> で修正しました。"
#                B) コード修正以外 (PR description 更新・既存コミット流用など) の返信:
#                     "<日本語 1 文>。"
#                   例: "PR description を更新しました。"
#                      "<FULL_SHA> で既に対応済みです。"
#   pr_number  : 省略可 (デフォルトは現在ブランチの PR)。
#
# 最終的に投稿される本文フォーマット:
#
#   <body>
#
#   ---
#   🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill
set -euo pipefail

comment_id="${1:?comment_id が必須です}"
body="${2:?body が必須です (例: \"<FULL_SHA> で修正しました。\")}"
pr_number="${3:-}"

if [[ -z "$pr_number" ]]; then
  pr_number=$(gh pr view --json number -q .number)
fi

owner_repo=$(gh repo view --json owner,name -q '[.owner.login, .name] | @tsv')
owner=$(printf '%s' "$owner_repo" | cut -f1)
repo=$(printf '%s' "$owner_repo" | cut -f2)

# 固定署名 (英語)。必ず本文末尾に付加される。
signature=$'\n\n---\n🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill'

full_body="${body}${signature}"

gh api -X POST \
  "repos/${owner}/${repo}/pulls/${pr_number}/comments" \
  -F in_reply_to="$comment_id" \
  -f body="$full_body"

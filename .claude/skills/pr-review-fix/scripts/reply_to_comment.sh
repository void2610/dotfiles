#!/usr/bin/env bash
# 指定したレビューコメントに対して、固定フォーマットで返信する。
#
# スクリプトが末尾に必ず Claude Code 署名行 (英語) を付加するので、
# 呼び出し側は本文 (日本語 1 文) だけ渡せばよい。
#
# 使い方:
#   ./reply_to_comment.sh <comment_id> <body> [pr_number]
#   ./reply_to_comment.sh <comment_id> -    [pr_number]   # body を stdin から読む
#
# 引数:
#   comment_id : レビューコメントの databaseId
#   body       : 日本語 1 文。以下の 2 パターンのみ使う。
#                A) コード修正の返信:
#                     "<FULL_SHA> で修正しました。"
#                   FULL_SHA は 40 文字の完全 SHA (バッククォート無し)。
#                   GitHub UI が自動でコミットリンクに整形する。
#                   複数コミットに跨る場合は読点区切り:
#                     "<SHA1>、<SHA2> で修正しました。"
#                B) コード修正以外 (PR description 更新・既存コミット流用など):
#                     "<日本語 1 文>。"
#                   例: "PR description を更新しました。"
#                      "<FULL_SHA> で既に対応済みです。"
#                body が "-" のときは標準入力から読む。バックスラッシュ・バック
#                クォート・`$(...)` 等のシェル特殊文字を含む本文を安全に渡したい
#                場合はこちらを使う (呼び出し元シェルの展開を回避):
#                     printf '%s' "<body>" | ./reply_to_comment.sh <comment_id> -
#   pr_number  : 省略可 (デフォルトは現在ブランチの PR)。
#
# 最終的に投稿される本文フォーマット:
#
#   <body>
#
#   ---
#   🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill
#
# 依存:
#   - gh CLI v2.4.0+ (authenticated)
#   - git (PR 自動検出時)
set -euo pipefail

# --- gh CLI の存在・バージョンチェック ---
if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLI が見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi
gh_min="2.4.0"
gh_ver=$(gh --version 2>/dev/null | head -n1 | awk '{print $3}')
if [[ -n "$gh_ver" ]]; then
  lowest=$(printf '%s\n%s\n' "$gh_min" "$gh_ver" | sort -V | head -n1)
  if [[ "$lowest" != "$gh_min" ]]; then
    echo "警告: gh ${gh_min}+ 推奨 (現在 ${gh_ver})。" >&2
  fi
fi

comment_id="${1:?comment_id が必須です}"
body="${2:?body が必須です (例: \"<FULL_SHA> で修正しました。\" または \"-\" で stdin 読み込み)}"
pr_number="${3:-}"

# body が "-" の場合は stdin から読み込む (特殊文字を含む本文の安全渡し用)
if [[ "$body" == "-" ]]; then
  body=$(cat)
  if [[ -z "$body" ]]; then
    echo "エラー: body が stdin 経由で指定されましたが空でした。" >&2
    exit 1
  fi
fi

if [[ -z "$pr_number" ]]; then
  pr_number=$(gh pr view --json number -q .number)
fi

# PR の base repository を PR URL から抽出 (fork からの PR 対応)
pr_url=$(gh pr view "$pr_number" --json url -q .url)
if [[ "$pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/[0-9]+$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
else
  echo "エラー: PR URL から owner/repo を抽出できませんでした: ${pr_url}" >&2
  exit 1
fi

# 固定署名 (英語)。必ず本文末尾に付加される。
signature=$'\n\n---\n🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill'

full_body="${body}${signature}"

gh api -X POST \
  "repos/${owner}/${repo}/pulls/${pr_number}/comments" \
  -F in_reply_to="$comment_id" \
  -f body="$full_body"

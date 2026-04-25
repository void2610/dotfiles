#!/usr/bin/env bash
# request-copilot-review.sh
# 指定された PR に GitHub Copilot を PR レビュアーとして依頼する。
# Usage: request-copilot-review.sh <pr_number_or_url>
#
# 仕組み:
#   GitHub の `requestReviews` GraphQL mutation は通常 `userIds` / `teamIds` を取るが、
#   Bot をレビュアーにする場合は `botIds` を使う。
#   Copilot PR Reviewer の bot ノード ID は全リポジトリで共通の固定値:
#     BOT_kgDOCnlnWA  ( login: copilot-pull-request-reviewer )
#
# 失敗例:
#   - リポジトリで Copilot PR レビュー機能が有効化されていない
#   - PR が既に Copilot レビュアーを持っている (重複依頼)
#   - 認証されたユーザに Copilot を呼び出す権限がない
#
# これらは PR 作成本体を妨げないよう、エラー時もシェル終了コード 1 で穏当に失敗させ、
# 呼び出し側 (pr-create スキル) で警告として扱う想定。

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pr_number_or_url>" >&2
  exit 2
fi

target="$1"

# PR の GraphQL ノード ID を取得 (リポジトリは gh が cwd から推論)
pr_id=$(gh pr view "$target" --json id --jq '.id' 2>/dev/null || true)
if [[ -z "$pr_id" ]]; then
  echo "⚠️  PR が見つかりませんでした: $target" >&2
  exit 1
fi

# Copilot PR レビュアー bot の global node ID (固定)
COPILOT_BOT_ID="BOT_kgDOCnlnWA"

# botIds は配列なので GraphQL リテラル形式で埋め込む
mutation=$(cat <<EOF
mutation {
  requestReviews(input: {pullRequestId: "$pr_id", botIds: ["$COPILOT_BOT_ID"]}) {
    pullRequest { number }
  }
}
EOF
)

response=$(gh api graphql -f query="$mutation" 2>&1) || {
  echo "⚠️  Copilot レビュー依頼に失敗しました:" >&2
  echo "$response" >&2
  exit 1
}

pr_num=$(echo "$response" | jq -r '.data.requestReviews.pullRequest.number // empty' 2>/dev/null || true)
if [[ -z "$pr_num" ]]; then
  echo "⚠️  Copilot レビュー依頼に失敗しました:" >&2
  echo "$response" >&2
  exit 1
fi

echo "✅ Copilot にレビューを依頼しました (PR #$pr_num)"

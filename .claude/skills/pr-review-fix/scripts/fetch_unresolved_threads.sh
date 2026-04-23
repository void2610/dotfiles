#!/usr/bin/env bash
# 現在のブランチに紐づく PR の、未解決 (isResolved=false) レビュースレッドを
# JSON 配列で標準出力に出す。
#
# 使い方:
#   ./fetch_unresolved_threads.sh                # 現在ブランチの PR を自動検出
#   ./fetch_unresolved_threads.sh <pr_number>    # PR 番号を明示
#
# 出力: reviewThreads.nodes のうち isResolved=false のものだけを残した JSON 配列。
#   各要素は { id, isResolved, isOutdated, path, comments: { nodes: [...] } } 形式。
#   id         : thread_id (Phase 7 の resolve で使う)
#   comments.nodes[].databaseId : comment_id (Phase 7 の返信で使う)
set -euo pipefail

pr_number="${1:-}"
if [[ -z "$pr_number" ]]; then
  pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
  if [[ -z "$pr_number" ]]; then
    echo "エラー: 現在のブランチに PR が紐づいていません。" >&2
    exit 1
  fi
fi

owner_repo=$(gh repo view --json owner,name -q '[.owner.login, .name] | @tsv')
owner=$(printf '%s' "$owner_repo" | cut -f1)
repo=$(printf '%s' "$owner_repo" | cut -f2)

gh api graphql \
  -F owner="$owner" \
  -F repo="$repo" \
  -F number="$pr_number" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          comments(first: 20) {
            nodes {
              databaseId
              body
              path
              line
              url
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}
' | jq '.data.repository.pullRequest.reviewThreads.nodes
        | map(select(.isResolved == false))'

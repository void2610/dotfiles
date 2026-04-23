#!/usr/bin/env bash
# 現在のブランチに紐づく PR の、未解決 (isResolved=false) レビュースレッドを
# NDJSON (1 行 1 thread オブジェクト) で標準出力に出す。
#
# 使い方:
#   ./fetch_unresolved_threads.sh                # 現在ブランチの PR を自動検出
#   ./fetch_unresolved_threads.sh <pr_number>    # PR 番号を明示
#
# 各 thread オブジェクトの主要フィールド:
#   id                               : thread_id (Phase 7 の resolve で使う)
#   isResolved / isOutdated / path
#   comments.nodes[].databaseId      : comment_id (Phase 7 の返信で使う)
#
# 特徴:
#   - jq は不要 (gh api --jq 内蔵 gojq を使う)
#   - gh api --paginate で reviewThreads 100 件超の大 PR も全取得
#   - fork から投げた PR でも base repository (レビューが付く upstream) を正しく参照
#
# 依存: gh CLI (authenticated), git (PR 自動検出時)
set -euo pipefail

pr_number="${1:-}"
if [[ -z "$pr_number" ]]; then
  pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
  if [[ -z "$pr_number" ]]; then
    echo "エラー: 現在のブランチに PR が紐づいていません。" >&2
    exit 1
  fi
fi

# PR の base repository (= レビューが所属するリポジトリ) を PR URL から抽出する。
# fork からの PR では base = upstream repo、本リポジトリ ≠ upstream なので
# `gh repo view` (cwd の git remote ベース) だと誤った owner/repo を掴んでしまう。
# `gh pr view --json url` は cwd の remote から PR を解決して base の URL を返すので、
# fork からでも正しく upstream の owner/repo が取れる。
pr_url=$(gh pr view "$pr_number" --json url -q .url)
if [[ "$pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/[0-9]+$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
else
  echo "エラー: PR URL から owner/repo を抽出できませんでした: ${pr_url}" >&2
  exit 1
fi

# reviewThreads を全ページ取得し、isResolved=false のものだけを NDJSON で出力。
# gh api --paginate は GraphQL でも $endCursor / pageInfo を検知して自動でページを回す。
gh api graphql --paginate \
  -F owner="$owner" \
  -F repo="$repo" \
  -F number="$pr_number" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
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
' --jq '.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false)'

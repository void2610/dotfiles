#!/usr/bin/env bash
# GitHub GraphQL mutation で指定した review thread を resolve する。
#
# 使い方:
#   ./resolve_thread.sh <thread_id>
#
# 引数:
#   thread_id : "PRRT_..." 形式の review thread ID。
#               fetch_unresolved_threads.sh の出力 nodes[].id で取得する。
set -euo pipefail

thread_id="${1:?thread_id が必須です (\"PRRT_...\" 形式)}"

gh api graphql -F threadId="$thread_id" -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}
'

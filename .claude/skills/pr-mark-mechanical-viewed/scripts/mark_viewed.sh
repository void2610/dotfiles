#!/usr/bin/env bash
# 使い方: mark_viewed.sh <owner/repo> <PR番号> <パス一覧ファイル>  (1 行 1 パス)
set -euo pipefail
repo=$1; num=$2; list=$3
id=$(gh api "repos/$repo/pulls/$num" --jq .node_id)
ok=0; ng=0
while IFS= read -r p; do
  [ -z "$p" ] && continue
  if gh api graphql -f id="$id" -f p="$p" \
      -f query='mutation($id:ID!,$p:String!){markFileAsViewed(input:{pullRequestId:$id,path:$p}){clientMutationId}}' >/dev/null; then
    ok=$((ok+1))
  else
    ng=$((ng+1)); echo "NG $p" >&2
  fi
done < "$list"
echo "ok=$ok ng=$ng"

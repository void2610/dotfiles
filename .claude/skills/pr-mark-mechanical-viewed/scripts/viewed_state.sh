#!/usr/bin/env bash
# 使い方: viewed_state.sh <owner/repo> <PR番号>  → "<state>\t<path>" を全ファイル分出す
set -euo pipefail
owner=${1%/*}; name=${1#*/}; num=$2
gh api graphql --paginate -F owner="$owner" -F name="$name" -F num="$num" -f query='
query($owner:String!,$name:String!,$num:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){pullRequest(number:$num){
    files(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{path viewerViewedState}}}}}' \
  --jq '.data.repository.pullRequest.files.nodes[]|"\(.viewerViewedState)\t\(.path)"'

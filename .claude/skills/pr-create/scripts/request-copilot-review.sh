#!/usr/bin/env bash
# 枠不足は依頼の時点では通り、後から Copilot が quota 不足の COMMENTED レビューを返すので、そのときは lite で頼み直す
# 失敗しても PR 作成本体は成功しているので、呼び出し側 (pr-create) は終了コード 1 を警告として扱う

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pr_number_or_url> [lite|balanced|max|auto]" >&2
  exit 2
fi

target="$1"
effort="${2:-}"

effort_arg=""
if [[ -n "$effort" ]]; then
  case "$effort" in
    lite|balanced|max|auto) effort_arg=", reviewEffort: $(echo "$effort" | tr '[:lower:]' '[:upper:]')" ;;
    *)
      echo "⚠️  effort は lite / balanced / max / auto のどれか: $effort" >&2
      exit 2
      ;;
  esac
fi

# PR の GraphQL ノード ID を取得 (番号だけならリポジトリは gh が cwd から推論)
pr_id=$(gh pr view "$target" --json id --jq '.id' 2>/dev/null || true)
if [[ -z "$pr_id" ]]; then
  echo "⚠️  PR が見つかりませんでした: $target" >&2
  exit 1
fi

mutation=$(cat <<EOF
mutation {
  requestCopilotCodeReview(input: {pullRequestId: "$pr_id"$effort_arg}) {
    success
    failureReason
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

success=$(echo "$response" | jq -r '.data.requestCopilotCodeReview.success // false' 2>/dev/null || echo false)
if [[ "$success" != "true" ]]; then
  reason=$(echo "$response" | jq -r '.data.requestCopilotCodeReview.failureReason // empty' 2>/dev/null || true)
  echo "⚠️  Copilot レビュー依頼に失敗しました${reason:+ ($reason)}:" >&2
  echo "$response" >&2
  exit 1
fi

pr_num=$(echo "$response" | jq -r '.data.requestCopilotCodeReview.pullRequest.number')
echo "✅ Copilot にレビューを依頼しました (PR #$pr_num${effort:+, effort=$effort})"

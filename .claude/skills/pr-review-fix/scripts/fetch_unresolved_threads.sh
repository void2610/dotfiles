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
# 依存:
#   - gh CLI v2.4.0+ (authenticated) — --paginate + GraphQL 対応が必要
#   - git (PR 自動検出時)
set -euo pipefail

# --- 純 Bash の SemVer 比較 ($1 < $2 なら 0 を返す) ---
# 理由: `sort -V` は GNU sort 依存で、macOS 標準の BSD sort では `illegal option -- V`
#       となり、本スクリプトは `set -e` 下で即終了してしまう。OS 非依存にするため
#       純 Bash で比較する (数値接尾辞除去にも対応)。
version_lt() {
  local lhs="$1" rhs="$2"
  local -a lhs_parts rhs_parts
  local i max lhs_part rhs_part
  IFS=. read -r -a lhs_parts <<< "$lhs"
  IFS=. read -r -a rhs_parts <<< "$rhs"
  max=${#lhs_parts[@]}
  if (( ${#rhs_parts[@]} > max )); then
    max=${#rhs_parts[@]}
  fi
  for ((i = 0; i < max; i++)); do
    lhs_part="${lhs_parts[i]:-0}"
    rhs_part="${rhs_parts[i]:-0}"
    # 末尾の非数値接尾辞 (例: "2.40.0-beta" の "-beta") を除去
    lhs_part="${lhs_part%%[^0-9]*}"
    rhs_part="${rhs_part%%[^0-9]*}"
    [[ -z "$lhs_part" ]] && lhs_part=0
    [[ -z "$rhs_part" ]] && rhs_part=0
    if ((10#$lhs_part < 10#$rhs_part)); then
      return 0
    fi
    if ((10#$lhs_part > 10#$rhs_part)); then
      return 1
    fi
  done
  return 1
}

# --- gh CLI の存在・バージョンチェック ---
if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLI が見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi
gh_min="2.4.0"
gh_ver=$(gh --version 2>/dev/null | head -n1 | awk '{print $3}')
if [[ -n "$gh_ver" ]] && version_lt "$gh_ver" "$gh_min"; then
  echo "警告: gh ${gh_min}+ 推奨 (現在 ${gh_ver})。--paginate / GraphQL が動かない可能性あり。" >&2
fi

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
          # スレッド内コメントは first: 100 まで取得する。
          # GitHub 上で 1 スレッドに 100 件超の返信が付くことは実務上稀なため、
          # reviewThreads と違い pagination は行わず単発取得で十分とする。
          # (以前は first: 20 だったが、議論が長いスレッドで後続コメントを取りこぼす問題があった)
          comments(first: 100) {
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

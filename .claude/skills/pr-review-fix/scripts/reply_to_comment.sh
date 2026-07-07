#!/usr/bin/env bash
# process_replies.sh 経由の呼び出しのみを想定し、body は検証済みの SHA 報告文が渡される前提 (詳細は SKILL.md Phase 7 参照)。
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
  echo "警告: gh ${gh_min}+ 推奨 (現在 ${gh_ver})。" >&2
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
  if ! pr_number=$(gh pr view --json number -q .number 2>/dev/null) || [[ -z "$pr_number" ]]; then
    echo "エラー: 現在のブランチに PR が紐づいていません。第 3 引数で PR 番号を明示してください。" >&2
    exit 1
  fi
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

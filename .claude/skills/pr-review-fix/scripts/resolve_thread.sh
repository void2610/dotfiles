#!/usr/bin/env bash
# GitHub GraphQL mutation で指定した review thread を resolve する。
#
# 使い方:
#   ./resolve_thread.sh <thread_id>
#
# 引数:
#   thread_id : "PRRT_..." 形式の review thread ID。
#               fetch_unresolved_threads.sh の出力 nodes[].id で取得する。
#
# 依存:
#   - gh CLI (authenticated)
set -euo pipefail

# --- gh CLI の存在・認証チェック ---
if ! command -v gh >/dev/null 2>&1; then
  echo "エラー: gh CLI が見つかりません。https://cli.github.com/ からインストールしてください。" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "エラー: gh が未認証です。'gh auth login' で事前にログインしてください。" >&2
  exit 1
fi

thread_id="${1:?thread_id が必須です (\"PRRT_...\" 形式)}"

# GraphQL mutation のエラー文を一時ファイルにキャプチャし、
# 403/forbidden 系なら triage 権限チェックのガイドを stderr に出す。
err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT

if ! gh api graphql -F threadId="$thread_id" -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}
' 2>"$err_file"; then
  cat "$err_file" >&2
  echo "エラー: review thread の resolve に失敗しました (thread_id=${thread_id})。" >&2
  if grep -Eiq '403|forbidden|permission|resource not accessible' "$err_file"; then
    echo "権限不足の可能性があります。以下を確認してください:" >&2
    echo "  - 実行中の 'gh' が想定した GitHub ホスト/アカウントで認証されていること ('gh auth status' で確認)" >&2
    echo "  - 対象リポジトリに triage 以上の権限を持つアカウントであること" >&2
    echo "  - 利用中トークンのスコープに 'repo' (または 'public_repo') が含まれていること" >&2
  fi
  exit 1
fi

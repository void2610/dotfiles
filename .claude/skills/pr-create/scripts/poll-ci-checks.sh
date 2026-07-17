#!/usr/bin/env bash
set -euo pipefail

pr=""
timeout=1800
interval=30
grace=120
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)  timeout="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --grace)    grace="$2"; shift 2 ;;
    -*) echo "不明なオプション: $1" >&2; exit 2 ;;
    *)  pr="$1"; shift ;;
  esac
done

if [[ -z "$pr" ]]; then
  pr=$(gh pr view --json number --jq '.number' 2>/dev/null || true)
  [[ -n "$pr" ]] || { echo "現在ブランチの PR を検出できません" >&2; exit 2; }
fi

# gh pr checks は fail 時 exit 1 / pending 時 exit 8 を返すため、JSON 出力で判定する
ci_summary() {
  local out
  out=$(gh pr checks "$pr" --json bucket --jq '[.[].bucket] | join(",")' 2>/dev/null) || true
  [[ -z "$out" ]] && { echo none; return; }
  [[ "$out" == *pending* ]] && { echo pending; return; }
  [[ "$out" == *fail* || "$out" == *cancel* ]] && { echo fail; return; }
  echo pass
}

start=$(date +%s)
deadline=$(( start + timeout ))
echo "PR #$pr の CI チェックを待機 (timeout=${timeout}s, interval=${interval}s, grace=${grace}s)"

while (( $(date +%s) < deadline )); do
  ci=$(ci_summary)
  # push 直後はチェック未登録で none に見えるため、grace 内は登録待ちとして扱う
  if [[ "$ci" == none ]] && (( $(date +%s) - start < grace )); then
    ci=pending
  fi
  if [[ "$ci" != pending ]]; then
    echo "ci=$ci pr=$pr"
    echo "CI チェックが完了しました (PR #$pr, 結果: $ci)"
    exit 0
  fi
  sleep "$interval"
done

echo "ci=timeout pr=$pr"
echo "タイムアウト: ${timeout}s 以内に CI チェックが完了しませんでした (PR #$pr)" >&2
exit 1

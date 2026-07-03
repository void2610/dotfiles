#!/usr/bin/env bash
set -euo pipefail

COPILOT_LOGIN="copilot-pull-request-reviewer"
FETCH_THREADS="$HOME/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh"

pr=""
timeout=900
interval=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)  timeout="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    -*) echo "不明なオプション: $1" >&2; exit 2 ;;
    *)  pr="$1"; shift ;;
  esac
done

if [[ -z "$pr" ]]; then
  pr=$(gh pr view --json number --jq '.number' 2>/dev/null || true)
  [[ -n "$pr" ]] || { echo "現在ブランチの PR を検出できません" >&2; exit 2; }
fi

copilot_review_count() {
  gh pr view "$pr" --json reviews \
    --jq "[.reviews[] | select(.author.login == \"$COPILOT_LOGIN\")] | length" 2>/dev/null || echo 0
}

# 再依頼後の再ポーリングでも使えるよう、開始時点からの増分を待つ
baseline=$(copilot_review_count)
deadline=$(( $(date +%s) + timeout ))
echo "PR #$pr の Copilot レビューを待機 (baseline=$baseline, timeout=${timeout}s, interval=${interval}s)"

while (( $(date +%s) < deadline )); do
  current=$(copilot_review_count)
  if (( current > baseline )); then
    unresolved="?"
    if [[ -x "$FETCH_THREADS" ]]; then
      # 取得失敗は "?" のまま残し「指摘 0 件」と誤認させない
      if out=$("$FETCH_THREADS" "$pr" 2>/dev/null); then
        [[ -z "$out" ]] && unresolved=0 || unresolved=$(echo "$out" | grep -c .)
      fi
    fi
    echo "copilot_review=arrived pr=$pr unresolved_threads=$unresolved"
    echo "Copilot レビューが到着しました (PR #$pr, 未解決スレッド ${unresolved} 件)"
    exit 0
  fi
  sleep "$interval"
done

echo "copilot_review=timeout pr=$pr"
echo "タイムアウト: ${timeout}s 以内に Copilot レビューが到着しませんでした (PR #$pr)" >&2
exit 1

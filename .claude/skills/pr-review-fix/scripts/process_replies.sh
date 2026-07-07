#!/usr/bin/env bash
# reply_eligible/reply_body の機械検証を通らないエントリは API を呼ばずにスキップする (詳細は SKILL.md Phase 7 参照)。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "エラー: jq が見つかりません。'brew install jq' 等でインストールしてください。" >&2
  exit 1
fi

mapping_file="${1:?mapping.json のパスが必須です}"
dry_run=false
if [[ "${2:-}" == "--dry-run" ]]; then
  dry_run=true
fi

if [[ ! -f "$mapping_file" ]]; then
  echo "エラー: mapping ファイルが存在しません: ${mapping_file}" >&2
  exit 1
fi

if ! jq empty "$mapping_file" >/dev/null 2>&1; then
  echo "エラー: mapping ファイルが不正な JSON です: ${mapping_file}" >&2
  exit 1
fi

# FULL_SHA (40 桁 16 進) を "、" 区切りで 1 個以上並べた文字列 + 固定サフィックス
sha_line_re='^([0-9a-f]{40})(、[0-9a-f]{40})*で修正しました。$'

count=$(jq 'length' "$mapping_file")
sent=0
skipped=0

for ((i = 0; i < count; i++)); do
  entry=$(jq ".[$i]" "$mapping_file")
  seq=$(echo "$entry" | jq -r '.seq // "?"')
  eligible=$(echo "$entry" | jq -r '.reply_eligible // false')
  already_replied=$(echo "$entry" | jq -r '.replied // false')
  already_resolved=$(echo "$entry" | jq -r '.resolved // false')
  comment_id=$(echo "$entry" | jq -r '.comment_id // ""')
  thread_id=$(echo "$entry" | jq -r '.thread_id // ""')
  body=$(echo "$entry" | jq -r '.reply_body // ""')
  commit_hash=$(echo "$entry" | jq -r '.commit_hash // ""')

  reason=""

  if [[ "$eligible" != "true" ]]; then
    reason="reply_eligible != true"
  elif [[ "$already_replied" == "true" ]]; then
    reason="既に replied=true (再送しない)"
  elif [[ -z "$comment_id" || -z "$thread_id" ]]; then
    reason="comment_id / thread_id が欠落"
  elif [[ -z "$body" ]]; then
    reason="reply_body が空"
  fi

  if [[ -z "$reason" ]] && ! [[ "$body" =~ $sha_line_re ]]; then
    reason="reply_body が \"<FULL_SHA> で修正しました。\" 形式に合致しない"
  fi

  # SHA 不一致は別コメントの SHA を貼る誤送信の兆候なので拒否する。
  if [[ -z "$reason" ]]; then
    if [[ -z "$commit_hash" ]]; then
      reason="commit_hash が未設定"
    else
      IFS='、' read -r -a hashes <<< "$commit_hash"
      for h in "${hashes[@]}"; do
        [[ -z "$h" ]] && continue
        if [[ "$body" != *"$h"* ]]; then
          reason="commit_hash (${h}) が reply_body に含まれていない"
          break
        fi
      done
    fi
  fi

  if [[ -n "$reason" ]]; then
    echo "[skip] #${seq} (comment_id=${comment_id:-?}): ${reason}" >&2
    ((++skipped))
    continue
  fi

  if [[ "$dry_run" == "true" ]]; then
    echo "[dry-run] #${seq} comment_id=${comment_id} thread_id=${thread_id} body=\"${body}\"" >&2
    ((++sent))
    continue
  fi

  echo "[send] #${seq} comment_id=${comment_id}" >&2
  if ! printf '%s' "$body" | "${script_dir}/reply_to_comment.sh" "$comment_id" -; then
    echo "[error] #${seq}: 返信に失敗しました。resolve はスキップします。" >&2
    continue
  fi

  if [[ "$already_resolved" != "true" ]]; then
    if ! "${script_dir}/resolve_thread.sh" "$thread_id"; then
      echo "[error] #${seq}: resolve に失敗しました (返信は成功済み)。" >&2
    fi
  fi

  # mapping.json を即時更新 (context 切れ時の再開・再実行時の重複送信防止)。
  tmp_file="$(mktemp)"
  jq "(.[$i].replied) = true | (.[$i].resolved) = true" "$mapping_file" > "$tmp_file"
  mv "$tmp_file" "$mapping_file"

  ((++sent))
done

echo "完了: 送信 ${sent} / スキップ ${skipped} (total=${count})" >&2

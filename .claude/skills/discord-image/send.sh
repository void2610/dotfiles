#!/usr/bin/env bash
# Discord webhook 経由で画像を送るユーティリティ。
# 使い方:
#   send.sh file <画像パス> [メッセージ]
#   send.sh screenshot [メッセージ] [-- <screencapture オプション...>]
#   send.sh url <画像URL> [説明]
#
# Webhook URL は ~/.config/claude/discord-webhook から読み込む。

set -euo pipefail

WEBHOOK_FILE="${HOME}/.config/claude/discord-webhook"

die() {
  echo "error: $*" >&2
  exit 1
}

require_webhook() {
  [[ -f "$WEBHOOK_FILE" ]] || die "webhook URL ファイルが見つかりません: $WEBHOOK_FILE
セットアップ手順:
  mkdir -p ~/.config/claude
  echo \"https://discord.com/api/webhooks/XXXX/YYYY\" > $WEBHOOK_FILE
  chmod 600 $WEBHOOK_FILE"
  WEBHOOK_URL=$(cat "$WEBHOOK_FILE")
  [[ -n "$WEBHOOK_URL" ]] || die "webhook URL が空です: $WEBHOOK_FILE"
}

# 文字列を JSON 文字列リテラルとして安全にエスケープする
json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

post_file() {
  local path=$1 message=${2-}
  [[ -f "$path" ]] || die "ファイルが見つかりません: $path"
  local size
  size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
  if (( size > 8 * 1024 * 1024 )); then
    echo "warn: ${size} bytes は Discord 無料サーバの 8MB 上限を超える可能性があります" >&2
  fi
  local payload
  payload=$(printf '{"content":%s}' "$(json_escape "$message")")
  curl -sS -f \
    -F "file1=@${path}" \
    -F "payload_json=${payload}" \
    "$WEBHOOK_URL" \
    && echo
}

cmd_file() {
  local path=${1-}
  [[ -n "$path" ]] || die "usage: send.sh file <画像パス> [メッセージ]"
  shift
  post_file "$path" "${*-}"
}

cmd_screenshot() {
  # `--` までをメッセージ、それ以降を screencapture オプションとして扱う
  local message_parts=() sc_opts=()
  local in_opts=0
  for arg in "$@"; do
    if (( in_opts )); then
      sc_opts+=("$arg")
    elif [[ "$arg" == "--" ]]; then
      in_opts=1
    else
      message_parts+=("$arg")
    fi
  done
  local message="${message_parts[*]-}"
  local shot
  shot=$(mktemp -t claude-shot).png
  # trap 設定時に $shot を展開してパスを埋め込む (関数を抜けた後の EXIT でも参照できるように)
  trap "rm -f '$shot'" EXIT
  # -x で常にシャッター音を消す。追加オプションがあれば付ける
  if (( ${#sc_opts[@]} )); then
    screencapture -x "${sc_opts[@]}" "$shot"
  else
    screencapture -x "$shot"
  fi
  [[ -s "$shot" ]] || die "スクリーンショットの取得に失敗しました (画面収録権限を確認してください)"
  post_file "$shot" "$message"
}

cmd_url() {
  local url=${1-}
  [[ -n "$url" ]] || die "usage: send.sh url <画像URL> [説明]"
  shift
  local description=${*-}
  local payload
  payload=$(printf '{"embeds":[{"image":{"url":%s},"description":%s}]}' \
    "$(json_escape "$url")" "$(json_escape "$description")")
  curl -sS -f \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$WEBHOOK_URL" \
    && echo
}

main() {
  local subcmd=${1-}
  [[ -n "$subcmd" ]] || die "usage: send.sh {file|screenshot|url} [args...]"
  shift
  require_webhook
  case "$subcmd" in
    file)       cmd_file "$@" ;;
    screenshot) cmd_screenshot "$@" ;;
    url)        cmd_url "$@" ;;
    *) die "unknown subcommand: $subcmd (file|screenshot|url のいずれか)" ;;
  esac
}

main "$@"

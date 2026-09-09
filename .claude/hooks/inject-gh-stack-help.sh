#!/usr/bin/env bash
# stacked PR 関連の依頼を検知し、gh stack の help を context 注入する UserPromptSubmit hook
set -euo pipefail

input=$(cat)
prompt=$(jq -r '.prompt // ""' <<<"$input")

stack_re='stack|スタック|積み(上げ)?PR|多段 ?PR'
grep -qiE "$stack_re" <<<"$prompt" || exit 0

# 同一セッションでは一度だけ注入する (毎プロンプトの context 肥大を防ぐ)
session_id=$(jq -r '.session_id // "unknown"' <<<"$input")
marker="${TMPDIR:-/tmp}/claude-gh-stack-help-${session_id}"
[[ -e "$marker" ]] && exit 0
touch "$marker"

help=$(gh stack --help 2>/dev/null) || exit 0

jq -n --arg help "$help" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("stacked PR 関連の依頼を検知した。この環境には gh の stack 拡張が導入済みである。stacked PR の作成・同期・再構成には手動の git 操作ではなく gh stack サブコマンドを優先して使うこと。以下は gh stack --help の出力:\n\n" + $help)}}'

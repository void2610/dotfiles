#!/usr/bin/env bash
# reset 済みブランチへのコミット積み直し依頼を検知し、権限を理由とした拒否を防ぐ UserPromptSubmit hook
set -euo pipefail

prompt=$(jq -r '.prompt // ""')

# reset 言及または積み直し系の語彙のいずれかで発火 (誤検知しても additionalContext 注入のみで無害)
grep -qiE 'reset|リセット|積み直|積みなお|コミットし直|コミットしなお|切り直|作り直|やり直' <<<"$prompt" || exit 0

jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: "reset はユーザーが既に完了しており、Claude が破壊的操作 (git reset 等) を実行する必要は無い。「権限上できない」等と拒否せず、まず git status / git log / git reflog で現状を確認し、作業ツリーの内容からコミットを積み直せ。"}}'

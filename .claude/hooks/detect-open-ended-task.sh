#!/usr/bin/env bash
# 受け入れ基準の無い開放的依頼を検知し、task-contract スキルの発動を決定論的に促す UserPromptSubmit hook
set -euo pipefail

prompt=$(jq -r '.prompt // ""')

# 開放的依頼の語彙 (誤検知しても additionalContext 注入のみで無害)
open_re='いい感じに|よしなに|自律的に|任せる|お任せ|PDCA|自由に(改善|修正|作|やっ)|なんとかして|うまく(やっ|し)といて|良さそうに|それっぽく'
grep -qE "$open_re" <<<"$prompt" || exit 0

jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: "開放的な依頼を検知した。作業を開始する前に task-contract スキルを発動し、受け入れ基準・可動範囲・検証手段・イテレーション上限を確認せよ (依頼文で全項目が明示済みの場合のみ省略可)。"}}'

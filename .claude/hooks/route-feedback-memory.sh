#!/usr/bin/env bash
# feedback メモリ保存時に、指導の適用スコープ判定と正しい階層への配置を強制する PostToolUse hook
set -euo pipefail
input=$(cat)
path=$(jq -r '.tool_input.file_path // ""' <<<"$input")

grep -qE '/\.claude/projects/[^/]+/memory/[^/]+\.md$' <<<"$path" || exit 0
grep -qE '^\s*type:\s*feedback' "$path" 2>/dev/null || exit 0

cat >&2 <<'EOF'
feedback メモリが保存された。この指導の適用スコープを判定し、正しい階層へ配置し直せ:
1. 全プロジェクト普遍 → 決定論化できるなら hook 化をユーザーに提案。できなければ ~/.claude/CLAUDE.md へ昇格し、メモリは削除
2. リポジトリ普遍 → repo の CLAUDE.md / .claude/skills へ (git 同期で全 worktree に届き、乖離が構造的に消える)。メモリは削除
3. このリポジトリの一時的・作業固有の知識 → メモリのままでよい。ただし陳腐化条件 (何が完了したら消すか) を本文に明記せよ
EOF
exit 2

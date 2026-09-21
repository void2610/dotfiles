// 各スキル (commit / pr-create / pr-review-fix / branch-create) は実コマンドに CLAUDE_GIT_SKILL=<skill> を前置する規約
const TARGET_RE = /\b(git\s+commit|git\s+push|gh\s+pr\s+create)\b/;
const MARKER_RE =
  /CLAUDE_GIT_SKILL=(commit|pr-create|pr-review-fix|branch-create)\b/;

export const gitSkillDeny = (command: string): string | undefined =>
  TARGET_RE.test(command) && !MARKER_RE.test(command)
    ? "git commit / git push / gh pr create の直接実行はブロックされました。commit / pr-create / pr-review-fix スキル経由で (CLAUDE_GIT_SKILL=<skill名> を前置して) 実行してください。"
    : undefined;

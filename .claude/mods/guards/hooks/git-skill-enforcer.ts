// grep のパターン等の引数に現れる語で止めないよう、コマンドの位置に来た git / gh だけを対象にする
const TARGET_RE =
  /(?:^|(?<!\\)[;&|({`\n]|\b(?:ba|z)?sh\s+-\w*c\s+["']|\beval\s+["']?)\s*(?:(?:\w+=\S*|!|env|command|exec|nohup|time|nice|xargs|if|then|else|elif|do|while|until)\s+)*(?:git(?:\s+-[Cc]\s+\S+)*\s+(?:commit|push)(?![\w-])|gh\s+pr\s+create\b)/;

// 各スキル (commit / push / pr-create / pr-review-fix / branch-create) は実コマンドに CLAUDE_GIT_SKILL=<skill> を前置する規約
const MARKER_RE =
  /CLAUDE_GIT_SKILL=(commit|push|pr-create|pr-review-fix|branch-create)\b/;

// ヒアドキュメントの本文は書き出す文章なので、行頭の git push をコマンドと取り違えないよう開始行だけ残す
const HEREDOC_RE = /<<-?[ \t]*(['"]?)(\w+)\1[^\n]*\n[\s\S]*?\n[ \t]*\2[ \t]*(?=\n|$)/g;
const withoutHeredocBodies = (command: string): string =>
  command.replace(HEREDOC_RE, (m) => m.slice(0, m.indexOf("\n")));

export const gitSkillDeny = (command: string): string | undefined =>
  TARGET_RE.test(withoutHeredocBodies(command)) && !MARKER_RE.test(command)
    ? "git commit / git push / gh pr create の直接実行はブロックされました。git commit は commit、git push は push、gh pr create は pr-create スキル経由で (CLAUDE_GIT_SKILL=<skill名> を前置して) 実行してください。"
    : undefined;

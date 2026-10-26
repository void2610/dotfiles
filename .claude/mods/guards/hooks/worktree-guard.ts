// worktree の置き場所はユーザーが決める。セッションが自分で増やすと、どのツリーで何が進んでいるかを追えなくなる
const WORKTREE_ADD_RE = /\bgit(\s+-C\s+\S+)?\s+worktree\s+add\b/;
const ALLOW_RE = /\bCLAUDE_ALLOW_WORKTREE=1\b/;

const REASON =
  "worktree の作成をブロック: セッションは worktree を作らない (サブモジュールの worktree も)。渡された作業ツリーの中でブランチを切って作業すること。ユーザーが明示的に worktree を求めたときだけ CLAUDE_ALLOW_WORKTREE=1 を前置する。";

export function worktreeAddDeny(cmd: string): string | undefined {
  if (WORKTREE_ADD_RE.test(cmd) && !ALLOW_RE.test(cmd)) return REASON;
  return undefined;
}

export function enterWorktreeDeny(): string {
  return REASON;
}

import type { Run } from "./caps";

const BRANCH_OP_RE =
  /\bgit(?:\s+-C\s+(\S+))?\s+(switch|checkout|worktree\s+add)\b/;
// "git checkout -- <path>" のファイル復元はブランチ移動ではないため許可
const CHECKOUT_PATHS_RE = /\bgit(\s+-C\s+\S+)?\s+checkout(\s+\S+)*\s+--(\s|$)/;
// ユーザー明示承認の escape (open PR ロックと unstack のみ。ship ロックは絶対)
const USER_ALLOW_RE = /(^|[^A-Za-z0-9_])SHIP_ALLOW_BRANCH_SWITCH=1/;
// unstack 以外の gh stack サブコマンドは stacked PR の正常運用なので見ない
const GH_STACK_UNSTACK_RE = /\bgh(\s+-R\s+\S+)?\s+stack\s+unstack\b/;
// 新規ブランチ・worktree の作成はスタック内判定の対象にしない (段を足すのは gh stack add)
const CREATES_RE =
  /(^|\s)(-c|-b|-B|--create|--orphan)(\s|$)|\bworktree\s+add\b/;
const NON_TARGET_WORDS = new Set([
  "git",
  "gh",
  "switch",
  "checkout",
  "worktree",
  "add",
  "&&",
  ";",
]);

export async function shipBranchLockDeny(
  run: Run,
  home: string | undefined,
  cmd: string,
): Promise<string | undefined> {
  const escaped = USER_ALLOW_RE.test(cmd);
  if (GH_STACK_UNSTACK_RE.test(cmd)) {
    return escaped
      ? undefined
      : "ブロック: gh stack unstack はスタックをローカルと GitHub の両方から削除する。作業フロー中は実行しないこと。必要ならユーザーに報告し、明示承認があった場合のみ 'SHIP_ALLOW_BRANCH_SWITCH=1 <cmd>' で再実行すること。";
  }

  const op = BRANCH_OP_RE.exec(cmd);
  if (!op || CHECKOUT_PATHS_RE.test(cmd)) return undefined;

  const creates = CREATES_RE.test(cmd);
  // スタックのブランチ名と照合するだけなので余分なトークンが混ざっても無害
  const targets = creates
    ? []
    : cmd
        .split(/\s+/)
        .filter((t) => t && !t.startsWith("-") && !NON_TARGET_WORDS.has(t));

  // -C 先 (サブモジュール等) のロックはそのリポジトリの ship 状態・PR で判定する
  const target = op[1]?.replace(/^(["'])(.*)\1$/, "$2");
  const runIn: Run = (argv, init) =>
    run(argv, target ? { ...init, cwd: target } : init);

  const inRepo =
    (await runIn(["git", "rev-parse", "--is-inside-work-tree"])).exitCode === 0;
  if (!inRepo) return undefined;

  // (1) ship フローのロック。exit 3 のみがロック検知 (guard 自体の失敗で誤ブロックしない)
  if (home) {
    const guard = await runIn([
      "bash",
      `${home}/.claude/skills/ship/scripts/ship.sh`,
      "guard",
      ...targets,
    ]);
    if (guard.exitCode === 3) {
      return `ブランチ操作をブロック: ${(guard.stdout + guard.stderr).trim()}`;
    }
  }

  if (escaped) return undefined;

  // (2) ship 未 init でも open PR があれば禁止
  const out = async (argv: readonly string[]) => {
    const r = await runIn(argv);
    return r.exitCode === 0 ? r.stdout.trim() : "";
  };
  const defaultBranch = (
    await out(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
  ).replace(/^origin\//, "");
  const current = await out(["git", "rev-parse", "--abbrev-ref", "HEAD"]);
  if (!current || !defaultBranch || current === defaultBranch) return undefined;

  const prState = await out([
    "gh",
    "pr",
    "view",
    "--json",
    "state",
    "--jq",
    ".state",
  ]);
  if (prState !== "OPEN") return undefined;

  const dirty = (await out(["git", "status", "--porcelain"])) !== "";

  // 同一スタック内の段への移動は stacked PR の正常運用なので未 push でも許可 (未コミットの変更は別の段へ引き連れるため不可)
  if (!dirty && targets.length > 0 && home) {
    const inStack = new Set(
      (
        await out([
          "bash",
          `${home}/.claude/skills/ship/scripts/ship.sh`,
          "stack-branches",
        ])
      )
        .split("\n")
        .filter(Boolean),
    );
    if (targets.some((t) => inStack.has(t))) return undefined;
  }

  // clean かつ push 済みなら失う作業が無いため許可 (worktree で連続タスクを受ける運用で毎回の承認待ちになる)
  if (!dirty) {
    let remoteRef = await out([
      "git",
      "rev-parse",
      "--abbrev-ref",
      "--symbolic-full-name",
      "@{u}",
    ]);
    if (!remoteRef) {
      const chk = await runIn([
        "git",
        "rev-parse",
        "--verify",
        "-q",
        `origin/${current}`,
      ]);
      if (chk.exitCode === 0) remoteRef = `origin/${current}`;
    }
    if (remoteRef) {
      const count = await runIn([
        "git",
        "rev-list",
        "--count",
        `${remoteRef}..HEAD`,
      ]);
      if (count.exitCode === 0 && count.stdout.trim() === "0") return undefined;
    }
  }

  return `ブランチ操作をブロック: 現在ブランチ '${current}' には OPEN な PR があり、未コミットまたは未 push の変更が残っています。commit / push で提出を完了させてから移動すること (同一スタック内の段への移動なら clean であれば未 push でも通ります)。それでも移動が必要ならユーザーに報告し指示を待ち、明示承認があった場合のみ 'SHIP_ALLOW_BRANCH_SWITCH=1 <cmd>' で再実行すること。`;
}

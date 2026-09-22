import type { Register } from "claude-code";
import { branchTrackDeny } from "./branch-track-guard";
import type { ReadFile, Run } from "./caps";
import { commentStyleNote } from "./comment-style-guard";
import { feedbackMemoryNote } from "./feedback-memory-router";
import { ghStackHelpNote } from "./gh-stack-help";
import { gitSkillDeny } from "./git-skill-enforcer";
import { resetRestackNote } from "./reset-restack-hint";
import { shipBranchLockDeny } from "./ship-branch-lock";
import { taskContractNote } from "./task-contract-trigger";

// エンジンは同一イベントの重複登録を拒否し、検証器は $ を import 越しに追えない。
// そのためイベント登録と $ の呼び出しは本ファイルに閉じ、機能本体は各ファイルの純関数に置く
export const register: Register = (on) => {
  on("prompt.submit", async ($, e, next) => {
    const run: Run = (argv) => $.process.run(argv);
    const notes = [
      taskContractNote(e.text),
      resetRestackNote(e.text),
      await ghStackHelpNote(run, e.text),
    ].filter((n): n is string => n !== undefined);
    if (notes.length === 0) return next(e);
    return next({ ...e, context: [...(e.context ?? []), ...notes] });
  });

  on("tool.call", { tool: "Bash" }, async ($, e, next) => {
    const run: Run = (argv) => $.process.run(argv);
    const home = await $.env.get("HOME");
    const deny =
      gitSkillDeny(e.command) ??
      branchTrackDeny(e.command) ??
      (await shipBranchLockDeny(run, home, e.command));
    if (deny !== undefined) return { deny };
    return next(e);
  });

  on("tool.call", { tool: "Edit" }, async ($, e, next) => {
    const r = await next(e);
    if (r.deny !== undefined || r.isError) return r;
    const run: Run = (argv) => $.process.run(argv);
    const readFile: ReadFile = (path) => $.fs.read(path);
    const notes = [
      await commentStyleNote(
        run,
        e.file_path,
        e.new_string,
        e.old_string,
        false,
      ),
      await feedbackMemoryNote(readFile, e.file_path),
    ].filter((n): n is string => n !== undefined);
    if (notes.length === 0) return r;
    return { ...r, context: [...(r.context ?? []), ...notes] };
  });

  on("tool.call", { tool: "Write" }, async ($, e, next) => {
    const r = await next(e);
    if (r.deny !== undefined || r.isError) return r;
    const run: Run = (argv) => $.process.run(argv);
    const readFile: ReadFile = (path) => $.fs.read(path);
    const notes = [
      await commentStyleNote(run, e.file_path, e.content, "", true),
      await feedbackMemoryNote(readFile, e.file_path),
    ].filter((n): n is string => n !== undefined);
    if (notes.length === 0) return r;
    return { ...r, context: [...(r.context ?? []), ...notes] };
  });
};

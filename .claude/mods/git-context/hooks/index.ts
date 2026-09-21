import type { Register } from "claude-code";

export const register: Register = (on) => {
  on("prompt.context", async ($, e, next) => {
    const run = async (argv: readonly string[]) => {
      const r = await $.process.run(argv);
      return r.exitCode === 0 ? r.stdout.replace(/\n$/, "") : undefined;
    };

    const inRepo = await run(["git", "rev-parse", "--is-inside-work-tree"]);
    if (inRepo === undefined) return next(e);

    const branch =
      (await run(["git", "rev-parse", "--abbrev-ref", "HEAD"])) ?? "?";
    const status = (await run(["git", "status", "--short"])) || "(クリーン)";
    let text = `現在のブランチ: ${branch}\n\n## git status --short\n${status}`;
    if (branch !== "main") {
      const log = await run(["git", "log", "--oneline", "main..HEAD"]);
      text += `\n\n## main からの差分コミット\n${log || "(なし)"}`;
    }

    return next({ ...e, blocks: [...e.blocks, { name: "gitStatus", text }] });
  });
};

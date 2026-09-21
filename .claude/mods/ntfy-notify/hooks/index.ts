import type { Register } from "claude-code";

export const register: Register = (on) => {
  on("turn.complete", async ($, e, next) => {
    // サブエージェントと中断は通知しない (旧 Stop hook 相当はメインループの完了のみ)
    if (!e.agentId && !e.isAborted) {
      const home = await $.env.get("HOME");
      if (home) {
        await $.process.run([
          "bash",
          `${home}/.claude/notify.sh`,
          "Stop",
          "success",
        ]);
      }
    }
    return next(e);
  });
};

import type { Register } from "claude-code";

export const register: Register = (on) => {
  on("turn.complete", async ($, e, next) => {
    // サブエージェントと中断は通知しない (旧 Stop hook 相当はメインループの完了のみ)
    if (!e.agentId && !e.isAborted) {
      const home = await $.env.get("HOME");
      // autopilot 実行中は毎ターンの完了が通知になってしまうため、停止時の通知 (autopilot Mod) だけにする
      const autopilot = `${home}/.claude/state/autopilot/sessions/${await $.session.id()}`;
      if (home && !(await $.fs.exists(autopilot))) {
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

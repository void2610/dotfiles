import type { Register } from "claude-code";

export const register: Register = (on) => {
  on("turn.complete", ($, e, next) => {
    // サブエージェントのターンと中断は通知しない (メインループの完了だけ知りたい)
    if (!e.agentId && !e.isAborted) {
      const sec = (e.durationMs / 1000).toFixed(1);
      const tok = e.usage
        ? ` · ${(e.usage.input_tokens + e.usage.output_tokens).toLocaleString()} tok`
        : "";
      $.ui.toast(`⏱ ${sec}s${tok}`);
    }
    return next(e);
  });
};

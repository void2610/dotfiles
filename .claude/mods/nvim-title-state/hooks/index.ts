import type { EngineInterface, Register } from "claude-code";

type State = "working" | "waiting" | "done" | "none";

async function send($: EngineInterface, state: State) {
  // nvim の :terminal から起動された時だけ $NVIM に親のソケットが入る
  const server = await $.env.get("NVIM");
  if (!server) return;
  // ターンの進行を nvim の応答待ちで止めないよう await しない
  $.process
    .run([
      "nvim",
      "--server",
      server,
      "--remote-expr",
      `luaeval('ClaudeTitleState(_A)', '${state}')`,
    ])
    .catch(() => {});
}

export const register: Register = (on) => {
  on("turn.start", async ($, e, next) => {
    await send($, "working");
    return next(e);
  });

  on("tool.check", async ($, e, next) => {
    const result = await next(e);
    // ask はモードの判定者へ回るため、auto モードでは分類器の判定中も一瞬 waiting になる
    if (e.tool_use_id && result.decision === "ask") await send($, "waiting");
    return result;
  });

  on("tool.call", async ($, e, next) => {
    const result = await next(e);
    await send($, "working");
    return result;
  });

  on("turn.complete", async ($, e, next) => {
    if (!e.agentId) await send($, "done");
    return next(e);
  });

  on("session.end", async ($, e, next) => {
    await send($, "none");
    return next(e);
  });
};

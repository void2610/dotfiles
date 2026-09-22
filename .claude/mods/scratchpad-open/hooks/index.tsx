import type { EngineInterface, Register } from "claude-code";

let fileCount = 0;
let watcherStarted = false;

async function scratchpadDir($: EngineInterface): Promise<string> {
  const id = await $.session.id();
  const root = await $.session.root();
  const uid = (await $.process.run(["id", "-u"])).stdout.trim();
  // scratchpad の実体パス規約 (ハーネス内部実装依存): /tmp/claude-<uid>/<root の / を - に置換>/<sessionId>/scratchpad
  return `/tmp/claude-${uid}/${root.replaceAll("/", "-")}/${id}/scratchpad`;
}

async function openScratchpad($: EngineInterface): Promise<string> {
  const dir = await scratchpadDir($);
  await $.process.run(["mkdir", "-p", dir]);
  await $.process.run(["open", dir]);
  return dir;
}

async function refreshCount($: EngineInterface): Promise<void> {
  const dir = await scratchpadDir($);
  const r = await $.process.run(["find", dir, "-type", "f"]);
  const n =
    r.exitCode === 0 ? r.stdout.split("\n").filter((l) => l !== "").length : 0;
  if (n !== fileCount) {
    fileCount = n;
    $.ui.invalidate("ui.render");
  }
}

function ensureWatcher($: EngineInterface): void {
  if (watcherStarted) return;
  watcherStarted = true;
  $.clock.every(5000, () => refreshCount($));
}

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.command.register({
      name: "scratchpad",
      description: "現セッションの scratchpad を Finder で開く",
    });
    ensureWatcher($);
    return next(e);
  });

  // リロード時は session.start が再発火しないため他フックからも起動できるようにする
  on("prompt.submit", ($, e, next) => {
    ensureWatcher($);
    return next(e);
  });

  on("command.run", { command: "scratchpad" }, async ($) => {
    return { text: `開いた: ${await openScratchpad($)}` };
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    if (fileCount === 0) return next(e);
    const { Box, Button } = $.ui.resolve(e);
    // pr-watch 等が同じ帯を使うため、チェーンの結果に自分のボタンを併記する
    const rest = await next(e);
    return (
      <Box flexDirection="column">
        {rest}
        <Button
          key="scratchpad"
          label={`scratchpad (${fileCount})`}
          plain
          dimColor
          onPress={() => void openScratchpad($)}
        />
      </Box>
    );
  });
};

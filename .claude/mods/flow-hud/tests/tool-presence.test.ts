import assert from "node:assert/strict";
import { test } from "node:test";
import { missingTools } from "../hooks/tool-presence.ts";

const specs = ["status", "init", "done", "skip"];

test("全部載っていれば何も欠けていない", () => {
  const listed = ["Bash", ...specs.map((n) => `mcp__flow-hud__${n}`)];
  assert.deepEqual(missingTools(listed, specs), []);
});

test("本体が MCP サーバーを外して一覧から消えたら、全部欠けている", () => {
  assert.deepEqual(missingTools(["Bash", "mcp__other__status"], specs), specs);
});

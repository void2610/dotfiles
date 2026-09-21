import { expect, test } from "claude-code/testing";

test("Manual モード (modes 空) で MANUAL バッジを描画する", async ($) => {
  for (const surface of ["terminal", "desktop"] as const) {
    const d = await $.ui.mount({
      plugin: "mode-badge",
      surface,
      component: "SessionMode",
      props: { modes: [] },
    });
    expect(await d.find({ type: "Text", text: /MANUAL/ })).toBeDefined();
  }
});

test("他モードのラベルがあるときは手を出さない", async ($, on) => {
  // プラグインが next(e) で素通しした先を、エンジンの代わりにテストが描く
  on("ui.render", ($$, e) => {
    const { Text } = $$.ui.resolve(e);
    return <Text>engine-fallback</Text>;
  });
  for (const surface of ["terminal", "desktop"] as const) {
    const d = await $.ui.mount({
      plugin: "mode-badge",
      surface,
      component: "SessionMode",
      props: { modes: ["⏵⏵ accept edits on"] },
    });
    expect(await d.find({ type: "Text", text: /MANUAL/ })).toBeUndefined();
    expect(await d.find({ text: /engine-fallback/ })).toBeDefined();
  }
});

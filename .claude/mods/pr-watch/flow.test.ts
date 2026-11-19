import { expect, mock, test } from "claude-code/testing";

const URL = "https://github.com/o/r/pull/353";

test("開いた PR を購読し、別のブランチへ移ってからのマージでセッションを起こす", async ($, on) => {
  let branch = "feat/x";
  let state = "OPEN";
  const submitted: string[] = [];
  const clock = mock.clock(on);
  const store = new Map<string, unknown>();
  on("store.get", (_, e) => ({ value: store.get(e.key) }));
  on("store.set", (_, e) => {
    store.set(e.key, e.value);
    return { value: undefined };
  });

  on("session.id", () => ({ value: "s1" }));
  on("session.start", (_, e) => ({ cwd: e.cwd }));
  on("ui.invalidate", () => ({ value: undefined }));
  on("prompt.submit", (_, e) => {
    submitted.push(e.text);
    return { text: e.text };
  });
  on("command.register", () => ({ value: { command: "pr-watch" } }));
  on("process.run", (_, e) => {
    const a = e.argv.join(" ");
    const ok = (stdout: string) => ({
      value: { exitCode: 0, stdout, stderr: "" },
    });
    if (a === "git rev-parse --abbrev-ref HEAD") return ok(branch);
    if (a.startsWith("git rev-parse")) return ok(`${branch}-sha`);
    if (a.startsWith("git symbolic-ref")) return ok("origin/main");
    if (a.startsWith("gh pr view")) {
      // main には PR が無いので、URL 指定の無い取得は失敗する
      if (!a.includes(URL) && branch === "main") {
        return {
          value: { exitCode: 1, stdout: "", stderr: "no pull requests found" },
        };
      }
      return ok(
        JSON.stringify({
          number: 353,
          state,
          url: URL,
          statusCheckRollup: [{ conclusion: "SUCCESS" }],
          reviews: [],
        }),
      );
    }
    return { value: { exitCode: 1, stdout: "", stderr: "" } };
  });

  // 監視は 5 秒おきのタイマーで回る
  await $.session.start({ cwd: "/", surface: "terminal", isInteractive: true });
  await clock.advance(5000);
  expect(store.get("subs:s1")).toEqual([{ number: 353, url: URL, nextAt: 0 }]);

  branch = "main";
  state = "MERGED";
  submitted.length = 0;
  await clock.advance(5000);

  expect(submitted.some((t) => t.includes("PR #353 がマージされた"))).toBe(
    true,
  );
  expect(store.get("subs:s1")).toEqual([]);
});

import type { EngineInterface, Register } from "claude-code";

const PANE_ID = "ship-hud";

type Phase = { name: string; state: string };
type ShipStatus =
  | { active: false }
  | {
      active: true;
      branch: string;
      goal: string;
      phases: Phase[];
      extras: Record<string, string>;
    };

function parseStatus(out: string): ShipStatus {
  const lines = out.split("\n");
  const head = (lines[0] ?? "").match(/^branch=(\S+) goal=(.*)$/);
  if (!head) return { active: false };
  const phases: Phase[] = [];
  const extras: Record<string, string> = {};
  for (const line of lines.slice(1)) {
    const p = line.match(/^ {2}(\w+): (\S+)/);
    if (p) {
      phases.push({ name: p[1] ?? "", state: p[2] ?? "" });
      continue;
    }
    const kv = line.match(/^(\w+)=(.*)$/);
    if (kv) extras[kv[1] ?? ""] = kv[2] ?? "";
  }
  return {
    active: true,
    branch: head[1] ?? "",
    goal: head[2] ?? "",
    phases,
    extras,
  };
}

// モジュール環境はセッション中維持される。ポーリングとレンダの共有状態
let status: ShipStatus = { active: false };
let raw = "";
let paneOpen = false;

async function refresh($: EngineInterface): Promise<boolean> {
  const home = await $.env.get("HOME");
  if (!home) return false;
  const r = await $.process.run([
    "bash",
    `${home}/.claude/skills/ship/scripts/ship.sh`,
    "status",
  ]);
  const out = (r.stdout + r.stderr).trim();
  const changed = out !== raw;
  raw = out;
  status = parseStatus(out);
  return changed;
}

const isPending = (p: Phase) => p.state !== "done" && p.state !== "skip";

// 人が閉じた後は自動再オープンで抗わない
let userClosed = false;
let pollerStarted = false;
// asked (コマンド経由) の open は 110 桁から、unasked (自動) は 144 桁から描画される
let paneAsked = false;

const paneDrawn = (columns: number | undefined) =>
  paneOpen && columns !== undefined && columns >= (paneAsked ? 110 : 144);

async function poll($: EngineInterface): Promise<void> {
  const changed = await refresh($);
  const active = status.active && status.phases.some(isPending);
  // セッション途中でフローが始まったケースも自動で開く
  if (active && !paneOpen && !userClosed) {
    await $.ui.open({ id: PANE_ID, title: "ship" });
    paneOpen = true;
    return;
  }
  if (changed && paneOpen) $.ui.invalidate("ui.render");
}

// リロード時はタイマー破棄 + session.start 非再発火のため、任意のフックから遅延起動できるようにする
function ensurePoller($: EngineInterface): void {
  if (pollerStarted) return;
  pollerStarted = true;
  $.clock.every(5000, () => poll($));
}

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.tool.register({
      name: "status",
      description:
        "ship フロー (開発パイプライン状態機械) の現在状態を返す。ship.sh status と同等の出力。Bash で ship.sh status を叩く代わりに使える。",
    });
    await $.command.register({
      name: "ship-hud",
      description: "ship フローの状態ペインを開閉する",
    });
    ensurePoller($);
    await poll($);
    return next(e);
  });

  on("prompt.submit", ($, e, next) => {
    ensurePoller($);
    return next(e);
  });

  on("ui.close", (_$, e, next) => {
    if (e.id === PANE_ID) {
      paneOpen = false;
      if (e.origin.kind === "person") userClosed = true;
    }
    return next(e);
  });

  on("command.run", { command: "ship-hud" }, async ($, _e, _next) => {
    if (paneOpen) {
      await $.ui.close({ id: PANE_ID });
      paneOpen = false;
      return { text: "ship HUD を閉じました" };
    }
    await refresh($);
    await $.ui.open({ id: PANE_ID, title: "ship" });
    paneOpen = true;
    paneAsked = true;
    return { text: "ship HUD を開きました" };
  });

  // 自前登録ツールは生成済み型の union に無いため RegExp matcher で束ねる
  on("tool.call", { tool: /^mcp__ship-hud__status$/ }, async ($, _e, _next) => {
    await refresh($);
    return { result: raw };
  });

  // Pane が幅ゲート (paneDrawn 参照) で描かれない環境向けに、最低限の現在地を 1 行出す
  on("ui.render", { component: "AbovePrompt" }, ($, e, next) => {
    if (!status.active || paneDrawn(e.viewport?.columns)) return next(e);
    const s = status;
    const cur = s.phases.find(isPending);
    if (!cur) return next(e);
    const done = s.phases.filter((p) => !isPending(p)).length;
    const { Box, Text } = $.ui.resolve(e);
    return (
      <Box>
        <Text dimColor>{"⛵ ship: "}</Text>
        <Text color="cyan" bold>{`→${cur.name}`}</Text>
        <Text dimColor>{` (${done}/${s.phases.length})`}</Text>
        {s.extras.worktree_dirty === "yes" && (
          <Text color="yellow">{" ⚠dirty"}</Text>
        )}
      </Box>
    );
  });

  on("ui.render", { component: "Pane" }, ($, e, next) => {
    if (e.component !== "Pane" || e.requestId !== PANE_ID) return next(e);
    const { Box, Text } = $.ui.resolve(e);
    if (!status.active) {
      return <Text dimColor>ship フローなし (ship.sh init で開始)</Text>;
    }
    const s = status;
    const cur = s.phases.findIndex(isPending);
    return (
      <Box flexDirection="column">
        <Text bold>{s.goal}</Text>
        <Text dimColor>{s.branch}</Text>
        <Text> </Text>
        {s.phases.map((p, i) => {
          const [icon, color] =
            p.state === "done"
              ? ["✓", "green"]
              : p.state === "skip"
                ? ["−", "yellow"]
                : i === cur
                  ? ["→", "cyan"]
                  : ["○", undefined];
          const label = p.state === "skip" ? `${p.name} (skip)` : p.name;
          return (
            <Text key={p.name} color={color} bold={i === cur}>
              {`${icon} ${label}`}
            </Text>
          );
        })}
        <Text> </Text>
        {s.extras.worktree_dirty === "yes" && (
          <Text color="yellow">⚠ 未コミット変更あり</Text>
        )}
        {s.extras.pr && <Text dimColor>{`PR: ${s.extras.pr}`}</Text>}
        {s.extras.ci && <Text dimColor>{`CI: ${s.extras.ci}`}</Text>}
      </Box>
    );
  });
};

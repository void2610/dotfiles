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
    await $.tool.register({
      name: "init",
      description:
        "ship フローを開始する (ship.sh init)。goal に開発目標を渡す。",
      inputSchema: {
        type: "object",
        properties: { goal: { type: "string" } },
        required: ["goal"],
      },
    });
    await $.tool.register({
      name: "done",
      description:
        "ship フローのフェーズ完了を検証して次へ進める (ship.sh done <phase>)。postcondition NG なら理由が返る。",
      inputSchema: {
        type: "object",
        properties: { phase: { type: "string" } },
        required: ["phase"],
      },
    });
    await $.tool.register({
      name: "skip",
      description:
        "ship フローのフェーズを理由付きで skip する (ship.sh skip <phase> <理由>)。ユーザー指示がある場合のみ使う。",
      inputSchema: {
        type: "object",
        properties: { phase: { type: "string" }, reason: { type: "string" } },
        required: ["phase", "reason"],
      },
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
    return { text: "ship HUD を開きました" };
  });

  // 自前登録ツールは生成済み型の union に無いため RegExp matcher で束ねる
  on("tool.call", { tool: /^mcp__ship-hud__status$/ }, async ($, _e, _next) => {
    await refresh($);
    return { result: raw };
  });

  on(
    "tool.call",
    { tool: /^mcp__ship-hud__(init|done|skip)$/ },
    async ($, e, _next) => {
      const a = e as unknown as {
        tool: string;
        goal?: string;
        phase?: string;
        reason?: string;
      };
      const home = await $.env.get("HOME");
      if (!home) return { deny: "HOME が取得できません" };
      const ship = `${home}/.claude/skills/ship/scripts/ship.sh`;
      const argv =
        a.tool === "mcp__ship-hud__init"
          ? [ship, "init", a.goal ?? ""]
          : a.tool === "mcp__ship-hud__done"
            ? [ship, "done", a.phase ?? ""]
            : [ship, "skip", a.phase ?? "", a.reason ?? ""];
      const r = await $.process.run(["bash", ...argv]);
      await refresh($);
      $.ui.invalidate("ui.render");
      return { result: (r.stdout + r.stderr).trim() || `exit=${r.exitCode}` };
    },
  );

  on("ui.render", { component: "Pane" }, ($, e, next) => {
    if (e.component !== "Pane" || e.requestId !== PANE_ID) return next(e);
    const { Box, Text, Button } = $.ui.resolve(e);
    if (!status.active) {
      return <Text dimColor>ship フローなし (ship.sh init で開始)</Text>;
    }
    const s = status;
    const shown = s.phases.filter((p) => p.state !== "skip");
    const cur = shown.findIndex(isPending);
    // report / quiz は承認コマンドをボタン化 (approve は HEAD SHA に紐づく)
    const approvable = s.phases.find(isPending)?.name;
    const approve =
      approvable === "report" || approvable === "quiz"
        ? async () => {
            const home = await $.env.get("HOME");
            if (!home) return;
            await $.process.run([
              "bash",
              `${home}/.claude/skills/ship/scripts/ship.sh`,
              approvable,
              "approve",
            ]);
            await refresh($);
            $.ui.invalidate("ui.render");
          }
        : undefined;
    return (
      <Box flexDirection="column">
        <Text bold>{s.goal}</Text>
        <Text dimColor>{s.branch}</Text>
        <Box flexWrap="wrap">
          {shown.map((p, i) => {
            const [icon, color] =
              p.state === "done"
                ? ["✓", "green"]
                : i === cur
                  ? ["→", "cyan"]
                  : ["○", undefined];
            return (
              <Text key={p.name} color={color} bold={i === cur}>
                {`${icon}${p.name} `}
              </Text>
            );
          })}
        </Box>
        {s.extras.worktree_dirty === "yes" && (
          <Text dimColor>未コミット変更あり</Text>
        )}
        {s.extras.pr && <Text dimColor>{`PR: ${s.extras.pr}`}</Text>}
        {s.extras.ci && <Text dimColor>{`CI: ${s.extras.ci}`}</Text>}
        {approve && (
          <Button
            key="ship-approve"
            label={`${approvable} approve`}
            onPress={approve}
          />
        )}
      </Box>
    );
  });
};

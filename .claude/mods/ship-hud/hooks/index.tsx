import type { EngineInterface, Register } from "claude-code";

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
let hidden = false;
let pollerStarted = false;

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

// リロード時はタイマー破棄 + session.start 非再発火のため、任意のフックから遅延起動できるようにする
function ensurePoller($: EngineInterface): void {
  if (pollerStarted) return;
  pollerStarted = true;
  $.clock.every(5000, async () => {
    if (await refresh($)) $.ui.invalidate("ui.render");
  });
}

const isPending = (p: Phase) => p.state !== "done" && p.state !== "skip";

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.tool.register({
      name: "status",
      description:
        "ship フロー (開発パイプライン状態機械) の現在状態を返す。ship.sh status と同等の出力。Bash で ship.sh status を叩く代わりに使える。",
    });
    await $.command.register({
      name: "ship-hud",
      description: "ship フローの状態表示 (プロンプト上の帯) を開閉する",
    });
    ensurePoller($);
    await refresh($);
    return next(e);
  });

  on("prompt.submit", ($, e, next) => {
    ensurePoller($);
    return next(e);
  });

  on("command.run", { command: "ship-hud" }, async ($, _e, _next) => {
    hidden = !hidden;
    if (!hidden) await refresh($);
    $.ui.invalidate("ui.render");
    return {
      text: hidden ? "ship HUD を隠しました" : "ship HUD を表示しました",
    };
  });

  // 自前登録ツールは生成済み型の union に無いため RegExp matcher で束ねる
  on("tool.call", { tool: /^mcp__ship-hud__status$/ }, async ($, _e, _next) => {
    await refresh($);
    return { result: raw };
  });

  // Pane は 144/110 桁の幅ゲートで狭い端末に描かれないため、幅制限の無い AbovePrompt 帯に描く
  on("ui.render", { component: "AbovePrompt" }, ($, e, next) => {
    if (hidden || !status.active) return next(e);
    const s = status;
    if (!s.phases.some(isPending)) return next(e);
    const { Box, Text } = $.ui.resolve(e);
    const cur = s.phases.findIndex(isPending);
    return (
      <Box flexDirection="column">
        <Text dimColor>{`⛵ ${s.goal}`}</Text>
        <Box flexWrap="wrap">
          {s.phases.map((p, i) => {
            const [icon, color] =
              p.state === "done"
                ? ["✓", "green"]
                : p.state === "skip"
                  ? ["−", "yellow"]
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
        {(s.extras.worktree_dirty === "yes" ||
          (s.extras.pr && s.extras.pr !== "none")) && (
          <Box flexWrap="wrap">
            {s.extras.worktree_dirty === "yes" && (
              <Text color="yellow">{"⚠ dirty "}</Text>
            )}
            {s.extras.pr && s.extras.pr !== "none" && (
              <Text
                dimColor
              >{`PR: ${s.extras.pr} (CI: ${s.extras.ci ?? "?"})`}</Text>
            )}
          </Box>
        )}
      </Box>
    );
  });
};

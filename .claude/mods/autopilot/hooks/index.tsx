import type {
  BoxProps,
  ButtonProps,
  ElementConstructor,
  EngineInterface,
  Register,
  TextProps,
  Timer,
} from "claude-code";
import {
  type Action,
  type AutopilotState,
  afterTurn,
  formatRemaining,
  isForeignOwner,
  type Limits,
  newState,
  parseCommand,
  requestStop,
  resume,
  setWait,
  stateKey,
  type TurnReason,
  withDefaults,
} from "./core";
import {
  compactInstructions,
  kickoffPrompt,
  STATE_FILES,
  statusText,
  templates,
  wakePrompt,
} from "./prompts";

type Loaded = { state: AutopilotState; dir: string };

// モジュール変数はリロードで初期化される。正は状態ファイル
let cache: Loaded | undefined;
let inTurn = false;
let wakePending = false;
let lastActivityAt = 0;
let lastTurnStartAt = 0;
let externalPromptAt = 0;
let waitTimer: Timer | undefined;
let watchdogStarted = false;

const WATCHDOG_MS = 30_000;
// ターン終了後この時間たっても次のターンが始まらなければ起こし直す (submit の取りこぼし・リロード対策)
const STALL_MS = 90_000;
const FINGERPRINT_SH =
  'cd "$1" 2>/dev/null && { git rev-parse HEAD; git diff HEAD | shasum; git ls-files -o --exclude-standard | shasum; } 2>/dev/null; cat "$2"/*.md 2>/dev/null | shasum';

const home = async ($: EngineInterface) => (await $.env.get("HOME")) ?? "";
const baseDir = (h: string) => `${h}/.claude/state/autopilot`;
const markerPath = (h: string, sid: string) => `${baseDir(h)}/sessions/${sid}`;

async function readState(
  $: EngineInterface,
  dir: string,
): Promise<AutopilotState | undefined> {
  const path = `${dir}/state.json`;
  try {
    if (!(await $.fs.exists(path))) return undefined;
    return JSON.parse(await $.fs.read(path)) as AutopilotState;
  } catch {
    return undefined;
  }
}

async function dirForCwd(
  $: EngineInterface,
): Promise<{ dir: string; root: string }> {
  const r = await $.process.run(["git", "rev-parse", "--show-toplevel"]);
  const root = r.exitCode === 0 ? r.stdout.trim() : await $.session.cwd();
  return { root, dir: `${baseDir(await home($))}/${stateKey(root)}` };
}

// 実行中はマーカーが状態ディレクトリを指すので、途中で cwd が変わっても見失わない
async function loadActive($: EngineInterface): Promise<Loaded | undefined> {
  const sid = await $.session.id();
  const marker = markerPath(await home($), sid);
  if (!(await $.fs.exists(marker))) return undefined;
  const dir = (await $.fs.read(marker)).trim();
  const state = await readState($, dir);
  if (state?.status !== "running" || state.sessionId !== sid) {
    return undefined;
  }
  return { state, dir };
}

async function loadAny($: EngineInterface): Promise<Loaded | undefined> {
  const active = await loadActive($);
  if (active) return active;
  const { dir } = await dirForCwd($);
  const state = await readState($, dir);
  return state ? { state, dir } : undefined;
}

async function save(
  $: EngineInterface,
  dir: string,
  state: AutopilotState,
): Promise<void> {
  const h = await home($);
  await $.process.run(["mkdir", "-p", dir, `${baseDir(h)}/sessions`]);
  await $.fs.write(`${dir}/state.json`, `${JSON.stringify(state, null, 2)}\n`);
  const marker = markerPath(h, state.sessionId);
  if (state.status === "running") await $.fs.write(marker, dir);
  else await $.process.run(["rm", "-f", marker]);
  cache = { state, dir };
  $.ui.invalidate("ui.render");
}

async function notify($: EngineInterface, message: string): Promise<void> {
  $.ui.toast(`autopilot: ${message}`);
  await $.process.run([
    "bash",
    `${await home($)}/.claude/notify.sh`,
    "Autopilot",
    message,
  ]);
}

// まだ 1 ターンも走っていなければ、どの経路から起こしても開始用の指示を渡す
const promptFor = (a: Loaded, now: number, note?: string) =>
  a.state.turns === 0
    ? kickoffPrompt(a.state, a.dir, now)
    : wakePrompt(a.state, a.dir, now, note);

function submitWake($: EngineInterface, text: string): void {
  if (wakePending) return;
  wakePending = true;
  // submit は次のターンが始まるまで解決しないため待たない
  void $.prompt.submit({ text }).catch(() => {
    wakePending = false;
  });
}

async function wakeNow($: EngineInterface, note?: string): Promise<void> {
  const a = await loadActive($);
  if (!a) return;
  const now = await $.clock.now();
  if (a.state.waitUntil !== undefined && a.state.waitUntil > now) return;
  submitWake($, promptFor(a, now, note));
}

function armWait($: EngineInterface, untilMs: number, now: number): void {
  waitTimer?.cancel();
  waitTimer = $.clock.after(Math.max(0, untilMs - now), () => {
    waitTimer = undefined;
    void wakeNow(
      $,
      "待機が明けた。待っていた対象 (CI・レビュー等) の状態を確認してから続けよ。",
    );
  });
}

async function perform(
  $: EngineInterface,
  action: Action,
  now: number,
): Promise<void> {
  switch (action.kind) {
    case "wake":
      // ユーザーや他の Mod (pr-watch) のプロンプトが既に積まれていれば、それが次のターンになる
      if (externalPromptAt > lastTurnStartAt) return;
      if (action.delayMs > 0) {
        $.clock.after(action.delayMs, () => void wakeNow($));
      } else {
        await wakeNow($);
      }
      return;
    case "wait":
      armWait($, action.untilMs, now);
      return;
    case "pause":
      await notify($, `一時停止: ${action.reason}`);
      return;
    case "stop":
      await notify($, `停止: ${action.reason}`);
      return;
    case "none":
      return;
  }
}

async function drive($: EngineInterface, reason: TurnReason): Promise<void> {
  const a = await loadActive($);
  if (!a) return;
  const now = await $.clock.now();
  const fp = await $.process.run([
    "bash",
    "-c",
    FINGERPRINT_SH,
    "_",
    a.state.root,
    a.dir,
  ]);
  const { state, action } = afterTurn(a.state, reason, now, fp.stdout.trim());
  await save($, a.dir, state);
  await perform($, action, now);
}

async function start(
  $: EngineInterface,
  goal: string,
  limits: Partial<Limits>,
): Promise<string> {
  const active = await loadActive($);
  if (active) return `autopilot は既に実行中です (目標: ${active.state.goal})`;
  const sid = await $.session.id();
  const now = await $.clock.now();
  const { dir, root } = await dirForCwd($);
  const prev = await readState($, dir);
  if (prev && isForeignOwner(prev, sid, now)) {
    return `このリポジトリでは別のセッションが autopilot を実行中です (目標: ${prev.goal})`;
  }
  const state = newState({
    sessionId: sid,
    goal,
    root,
    now,
    limits: withDefaults(limits),
  });
  await save($, dir, state);
  const files = templates(state);
  for (const name of STATE_FILES) {
    const path = `${dir}/${name}`;
    // 契約は目標ごとに作り直し、backlog や決定ログは前回分を引き継ぐ
    if (name === "contract.md" || !(await $.fs.exists(path))) {
      await $.fs.write(path, files[name]);
    }
  }
  lastActivityAt = now;
  // コマンドやツールの処理中に submit すると通らないことがあるため、処理を抜けてから送る
  $.clock.after(0, () => void wakeNow($));
  return `autopilot を開始しました。\n${statusText(state, dir, now)}`;
}

async function halt(
  $: EngineInterface,
  status: "paused" | "stopped",
  reason: string,
): Promise<string> {
  const a = await loadAny($);
  if (!a || a.state.status === "stopped") return statusText(undefined, "", 0);
  if (status === "paused" && a.state.status === "paused") {
    return "autopilot は既に一時停止中です";
  }
  waitTimer?.cancel();
  waitTimer = undefined;
  const now = await $.clock.now();
  await save($, a.dir, { ...a.state, status, reason, updatedAt: now });
  return status === "paused"
    ? "autopilot を一時停止しました (/autopilot resume で再開)"
    : "autopilot を停止しました";
}

async function resumeRun(
  $: EngineInterface,
  limits: Partial<Limits>,
): Promise<string> {
  const a = await loadAny($);
  if (!a || a.state.status === "stopped") {
    return "再開できる autopilot がありません (/autopilot start <目標> で開始)";
  }
  const sid = await $.session.id();
  const now = await $.clock.now();
  if (a.state.status === "running" && a.state.sessionId === sid) {
    return "autopilot は既に実行中です";
  }
  if (isForeignOwner(a.state, sid, now)) {
    return `別のセッションが autopilot を実行中です (目標: ${a.state.goal})`;
  }
  const state = resume(a.state, { sessionId: sid, now, limits });
  await save($, a.dir, state);
  lastActivityAt = now;
  $.clock.after(0, () => void wakeNow($, "一時停止から再開した。"));
  return `autopilot を再開しました。\n${statusText(state, a.dir, now)}`;
}

async function runCommand($: EngineInterface, args: string): Promise<string> {
  const c = parseCommand(args);
  switch (c.kind) {
    case "error":
      return c.message;
    case "start":
      return start($, c.goal, c.limits);
    case "resume":
      return resumeRun($, c.limits);
    case "pause":
      return halt($, "paused", "ユーザーが一時停止した");
    case "stop":
      return halt($, "stopped", "ユーザーが停止した");
    case "status": {
      const a = await loadAny($);
      return statusText(a?.state, a?.dir ?? "", await $.clock.now());
    }
  }
}

async function stopByModel(
  $: EngineInterface,
  reason: string,
  evidence: string,
): Promise<string> {
  const a = await loadActive($);
  if (!a) return "autopilot は動いていません";
  const now = await $.clock.now();
  const r = requestStop(a.state, now);
  if (!r.accepted) {
    await save($, a.dir, r.state);
    return `停止要求を一度差し戻します。autopilot-playbook の探索順をすべて実施したかを確かめ、見つかった作業は ${a.dir}/backlog.md に追記して着手してください。本当に尽きている (または残りがすべて blocked.md 行き) なら、各探索ステップで何を調べ何が無かったかを evidence に書いてもう一度呼んでください。`;
  }
  await save($, a.dir, {
    ...r.state,
    reason: `完了を宣言: ${reason}`,
  });
  await $.fs.write(
    `${a.dir}/log.md`,
    `${await $.fs.read(`${a.dir}/log.md`).catch(() => "# 進捗ログ\n")}\n## 停止 (${new Date(now).toLocaleString("ja-JP")})\n理由: ${reason}\n\n${evidence}\n`,
  );
  await notify($, `完了: ${reason}`);
  return "autopilot を停止しました。最後に、やったこと・blocked.md に残したこと・決定ログの要点をユーザー向けに短く報告してください。";
}

async function waitByModel(
  $: EngineInterface,
  minutes: number,
  reason: string,
): Promise<string> {
  const a = await loadActive($);
  if (!a) return "autopilot は動いていません";
  const now = await $.clock.now();
  const state = setWait(a.state, now, minutes, reason);
  await save($, a.dir, state);
  armWait($, state.waitUntil ?? now, now);
  return `待機を設定しました (あと ${formatRemaining((state.waitUntil ?? now) - now)})。このターンはここで終えてください。待機が明けたら起こします。`;
}

async function tick($: EngineInterface): Promise<void> {
  const a = await loadAny($);
  const changed = JSON.stringify(a) !== JSON.stringify(cache);
  cache = a;
  if (changed || a?.state.status === "running") $.ui.invalidate("ui.render");
  if (a?.state.status !== "running") return;
  if (a.state.sessionId !== (await $.session.id())) return;
  if (inTurn || wakePending || externalPromptAt > lastTurnStartAt) return;
  const now = await $.clock.now();
  const s = a.state;
  if (s.waitUntil !== undefined && s.waitUntil > now) {
    if (!waitTimer) armWait($, s.waitUntil, now);
    return;
  }
  if (now - lastActivityAt < STALL_MS) return;
  submitWake($, promptFor(a, now));
}

// リロードで session.start が再発火しない版もあったため、どのフックからでも起動できるようにする
function ensureWatchdog($: EngineInterface): void {
  if (watchdogStarted) return;
  watchdogStarted = true;
  $.clock.every(WATCHDOG_MS, () => void tick($));
}

type Ui = {
  Box: ElementConstructor<BoxProps>;
  Text: ElementConstructor<TextProps>;
  Button: ElementConstructor<ButtonProps>;
};

function renderHud($: EngineInterface, ui: Ui, a: Loaded, now: number) {
  const { Box, Text, Button } = ui;
  const s = a.state;
  const running = s.status === "running";
  const waiting = s.waitUntil !== undefined && s.waitUntil > now;
  const summary = running
    ? `${s.turns}/${s.maxTurns} · 残り ${formatRemaining(s.deadlineAt - now)} · 進捗なし ${s.idleTurns}/${s.idleLimit}`
    : `一時停止: ${s.reason ?? ""}`;
  const act = (fn: () => Promise<string>) => async () => {
    $.ui.toast(await fn());
  };
  return (
    <Box flexDirection="column">
      <Box width="100%">
        <Box flexGrow={1} flexShrink={1}>
          <Text wrap="truncate">
            <Text bold color={running ? "green" : "yellow"}>
              {running ? "autopilot ▶ " : "autopilot ⏸ "}
            </Text>
            <Text dimColor>{summary}</Text>
          </Text>
        </Box>
        <Box flexShrink={0} marginLeft={1}>
          <Button
            key="autopilot-toggle"
            label={running ? "[一時停止]" : "[再開]"}
            plain
            dimColor
            onPress={act(() =>
              running
                ? halt($, "paused", "ユーザーが一時停止した")
                : resumeRun($, {}),
            )}
          />
          <Button
            key="autopilot-stop"
            label="[停止]"
            plain
            dimColor
            onPress={act(() => halt($, "stopped", "ユーザーが停止した"))}
          />
        </Box>
      </Box>
      <Text dimColor wrap="truncate">
        {waiting
          ? `⏳ 待機 あと ${formatRemaining((s.waitUntil ?? now) - now)} (${s.waitReason ?? ""}) · ${s.goal}`
          : s.goal}
      </Text>
    </Box>
  );
}

const TOOL_RE = /^mcp__autopilot__(start|stop|wait|status)$/;

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    await $.command.register({
      name: "autopilot",
      description:
        "自走モード: start <目標> [--hours N --turns N --idle N] / pause / resume / stop / status",
    });
    await $.tool.register({
      name: "start",
      description:
        "autopilot (自走モード) を開始する。ユーザーが autopilot・自走での作業を頼んだときに使う。以後はターンが終わるたびに次のターンが自動で始まる。",
      isDeferred: false,
      inputSchema: {
        type: "object",
        properties: {
          goal: { type: "string", description: "目標" },
          hours: { type: "number", description: "時間の上限 (既定 8)" },
          turns: { type: "number", description: "ターン数の上限 (既定 300)" },
        },
        required: ["goal"],
      },
    });
    await $.tool.register({
      name: "stop",
      description:
        "autopilot を終える。backlog が空で探索しても作業が見つからない、または残りがすべて人間待ちのときだけ使う。1 回目は必ず差し戻される。",
      isDeferred: false,
      inputSchema: {
        type: "object",
        properties: {
          reason: { type: "string", description: "終える理由" },
          evidence: {
            type: "string",
            description: "探索順の各ステップで何を調べ、何が無かったか",
          },
        },
        required: ["reason", "evidence"],
      },
    });
    await $.tool.register({
      name: "wait",
      description:
        "CI やレビューなど外部の完了を待つ間、autopilot の起床を止める (最大 60 分)。他に進められる項目があるなら使わずにそちらを進める。",
      isDeferred: false,
      inputSchema: {
        type: "object",
        properties: {
          minutes: { type: "number" },
          reason: { type: "string", description: "何を待つか" },
        },
        required: ["minutes", "reason"],
      },
    });
    await $.tool.register({
      name: "status",
      description:
        "autopilot の状態 (ターン数・残り時間・状態ディレクトリ) を返す。",
      isDeferred: false,
    });
    lastActivityAt = await $.clock.now();
    ensureWatchdog($);
    cache = await loadAny($);
    return next(e);
  });

  on("prompt.submit", async ($, e, next) => {
    ensureWatchdog($);
    if (e.origin.kind !== "plugin" || e.origin.name !== $.plugin.name) {
      externalPromptAt = await $.clock.now();
    }
    return next(e);
  });

  on("turn.start", async ($, e, next) => {
    inTurn = true;
    wakePending = false;
    lastTurnStartAt = await $.clock.now();
    return next(e);
  });

  on("turn.complete", async ($, e, next) => {
    const r = await next(e);
    if (e.agentId) return r;
    inTurn = false;
    lastActivityAt = await $.clock.now();
    try {
      await drive($, e.reason);
    } catch {
      // 駆動に失敗してもウォッチドッグが起こし直す
    }
    return r;
  });

  on("session.compact", async ($, e, next) => {
    if (e.agentId) return next(e);
    const a = await loadActive($);
    if (!a) return next(e);
    const add = compactInstructions(a.dir);
    return next({
      ...e,
      instructions: e.instructions ? `${e.instructions}\n\n${add}` : add,
    });
  });

  on("command.run", { command: "autopilot" }, async ($, e) => ({
    text: await runCommand($, e.args),
  }));

  // 自前登録ツールは生成済み型の union に無いため RegExp matcher で束ねる
  on("tool.call", { tool: TOOL_RE }, async ($, e) => {
    const a = e as unknown as {
      tool: string;
      goal?: string;
      hours?: number;
      turns?: number;
      reason?: string;
      evidence?: string;
      minutes?: number;
    };
    const name = TOOL_RE.exec(a.tool)?.[1];
    let result: string;
    if (name === "start") {
      result = await start($, a.goal ?? "", { hours: a.hours, turns: a.turns });
    } else if (name === "stop") {
      result = await stopByModel($, a.reason ?? "", a.evidence ?? "");
    } else if (name === "wait") {
      result = await waitByModel($, a.minutes ?? 10, a.reason ?? "");
    } else {
      const l = await loadAny($);
      result = statusText(l?.state, l?.dir ?? "", await $.clock.now());
    }
    return { result };
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    const a = cache;
    if (!a || a.state.status === "stopped") return next(e);
    const ui = $.ui.resolve(e);
    const rest = await next(e);
    const now = await $.clock.now();
    return (
      <ui.Box flexDirection="column">
        {rest}
        {renderHud($, ui, a, now)}
      </ui.Box>
    );
  });
};

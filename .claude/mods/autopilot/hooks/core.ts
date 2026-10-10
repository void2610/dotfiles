export type Status = "running" | "paused" | "stopped";

export type AutopilotState = {
  version: 1;
  status: Status;
  sessionId: string;
  goal: string;
  root: string;
  startedAt: number;
  deadlineAt: number;
  maxTurns: number;
  turns: number;
  idleLimit: number;
  idleTurns: number;
  errorTurns: number;
  fingerprint: string;
  stopRequests: number;
  waitUntil?: number;
  waitReason?: string;
  reason?: string;
  updatedAt: number;
};

export type Limits = { hours: number; turns: number; idle: number };

export const DEFAULT_LIMITS: Limits = { hours: 8, turns: 300, idle: 4 };

export function withDefaults(p: Partial<Limits>): Limits {
  return {
    hours: p.hours ?? DEFAULT_LIMITS.hours,
    turns: p.turns ?? DEFAULT_LIMITS.turns,
    idle: p.idle ?? DEFAULT_LIMITS.idle,
  };
}

const HOUR_MS = 3_600_000;
const MAX_WAIT_MIN = 60;
const MAX_ERROR_TURNS = 3;
const ERROR_BACKOFF_MS = 30_000;
// 所有セッションがこれ以上更新していなければ、別セッションからの開始・再開を許す
export const STALE_OWNER_MS = 30 * 60_000;

export type TurnReason = "answer" | "aborted" | "refusal" | "error";

export type Action =
  | { kind: "none" }
  | { kind: "wake"; delayMs: number }
  | { kind: "wait"; untilMs: number }
  | { kind: "pause"; reason: string }
  | { kind: "stop"; reason: string };

export function newState(p: {
  sessionId: string;
  goal: string;
  root: string;
  now: number;
  limits: Limits;
}): AutopilotState {
  return {
    version: 1,
    status: "running",
    sessionId: p.sessionId,
    goal: p.goal,
    root: p.root,
    startedAt: p.now,
    deadlineAt: p.now + p.limits.hours * HOUR_MS,
    maxTurns: p.limits.turns,
    turns: 0,
    idleLimit: p.limits.idle,
    idleTurns: 0,
    errorTurns: 0,
    fingerprint: "",
    stopRequests: 0,
    updatedAt: p.now,
  };
}

export function afterTurn(
  s: AutopilotState,
  reason: TurnReason,
  now: number,
  fingerprint: string,
): { state: AutopilotState; action: Action } {
  if (s.status !== "running") return { state: s, action: { kind: "none" } };
  const base = { ...s, updatedAt: now };
  const halt = (kind: "pause" | "stop", why: string) => ({
    state: {
      ...base,
      status: kind === "pause" ? "paused" : "stopped",
      reason: why,
    } as AutopilotState,
    action: { kind, reason: why } as Action,
  });

  if (reason === "aborted")
    return halt("pause", "Esc で中断されたため一時停止");
  if (reason === "refusal")
    return halt("pause", "モデルが応答を拒否したため一時停止");
  if (reason === "error") {
    const errorTurns = s.errorTurns + 1;
    if (errorTurns >= MAX_ERROR_TURNS) {
      return halt("pause", `API エラーが ${errorTurns} 回続いたため一時停止`);
    }
    return {
      state: { ...base, errorTurns },
      action: { kind: "wake", delayMs: ERROR_BACKOFF_MS * errorTurns },
    };
  }

  const turns = s.turns + 1;
  const progressed = fingerprint !== s.fingerprint;
  const waiting = s.waitUntil !== undefined && s.waitUntil > now;
  // 待機中のターンは進捗が無くて当然なので数えない
  const idleTurns = progressed || waiting ? 0 : s.idleTurns + 1;
  const next: AutopilotState = {
    ...base,
    turns,
    errorTurns: 0,
    fingerprint,
    idleTurns,
    stopRequests: progressed ? 0 : s.stopRequests,
  };
  const halted = (why: string) => ({
    state: { ...next, status: "stopped", reason: why } as AutopilotState,
    action: { kind: "stop", reason: why } as Action,
  });

  if (now >= s.deadlineAt) return halted("時間の上限に達した");
  if (turns >= s.maxTurns)
    return halted(`ターン数の上限 (${s.maxTurns}) に達した`);
  if (idleTurns >= s.idleLimit) {
    return halted(
      `${idleTurns} ターン続けて進捗 (差分・状態ファイルの変化) が無い`,
    );
  }
  if (waiting && s.waitUntil !== undefined) {
    return { state: next, action: { kind: "wait", untilMs: s.waitUntil } };
  }
  const cleared = { ...next, waitUntil: undefined, waitReason: undefined };
  return { state: cleared, action: { kind: "wake", delayMs: 0 } };
}

// 1 回目の停止要求は必ず差し戻し、探索をやり切らせてから受け付ける
export function requestStop(
  s: AutopilotState,
  now: number,
): { accepted: boolean; state: AutopilotState } {
  if (s.stopRequests === 0) {
    return {
      accepted: false,
      state: { ...s, stopRequests: 1, updatedAt: now },
    };
  }
  return { accepted: true, state: { ...s, status: "stopped", updatedAt: now } };
}

export function setWait(
  s: AutopilotState,
  now: number,
  minutes: number,
  reason: string,
): AutopilotState {
  const m = Math.min(Math.max(1, Math.round(minutes)), MAX_WAIT_MIN);
  return {
    ...s,
    waitUntil: now + m * 60_000,
    waitReason: reason,
    updatedAt: now,
  };
}

export function resume(
  s: AutopilotState,
  p: { sessionId: string; now: number; limits: Partial<Limits> },
): AutopilotState {
  const hours = p.limits.hours;
  const expired = s.deadlineAt <= p.now;
  const deadlineAt =
    hours !== undefined
      ? p.now + hours * HOUR_MS
      : expired
        ? p.now + DEFAULT_LIMITS.hours * HOUR_MS
        : s.deadlineAt;
  const extra = p.limits.turns;
  const maxTurns =
    extra !== undefined
      ? s.turns + extra
      : s.turns >= s.maxTurns
        ? s.turns + DEFAULT_LIMITS.turns
        : s.maxTurns;
  return {
    ...s,
    status: "running",
    sessionId: p.sessionId,
    deadlineAt,
    maxTurns,
    idleLimit: p.limits.idle ?? s.idleLimit,
    idleTurns: 0,
    errorTurns: 0,
    stopRequests: 0,
    reason: undefined,
    updatedAt: p.now,
  };
}

export function isForeignOwner(
  s: AutopilotState,
  sessionId: string,
  now: number,
): boolean {
  return (
    s.status === "running" &&
    s.sessionId !== sessionId &&
    now - s.updatedAt < STALE_OWNER_MS
  );
}

export type Command =
  | { kind: "start"; goal: string; limits: Partial<Limits> }
  | { kind: "resume"; limits: Partial<Limits> }
  | { kind: "stop" | "pause" | "status" }
  | { kind: "error"; message: string };

const FLAG_RE = /--(hours|turns|idle)(?:=|\s+)(\d+(?:\.\d+)?)/g;

export function parseCommand(args: string): Command {
  const limits: Partial<Limits> = {};
  for (const m of args.matchAll(FLAG_RE)) {
    const key = m[1] as keyof Limits;
    const value = Number(m[2]);
    if (!(value > 0))
      return { kind: "error", message: `--${key} は正の数で指定してください` };
    limits[key] = value;
  }
  const rest = args.replace(FLAG_RE, " ").trim();
  const [head = "", ...tail] = rest.split(/\s+/);
  if (rest === "" || head === "status") return { kind: "status" };
  if (head === "stop" || head === "pause") return { kind: head };
  if (head === "resume") return { kind: "resume", limits };
  const goal = (head === "start" ? tail.join(" ") : rest).trim();
  if (goal === "")
    return {
      kind: "error",
      message: "目標を指定してください: /autopilot start <目標>",
    };
  return { kind: "start", goal, limits };
}

// bash 側 (ship.sh 等) でも ${root//[^A-Za-z0-9._-]/-} で同じキーを作れる形にしておく
export const stateKey = (root: string): string =>
  root.replace(/[^A-Za-z0-9._-]/g, "-");

export function formatRemaining(ms: number): string {
  if (ms <= 0) return "0m";
  const totalMin = Math.ceil(ms / 60_000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return h > 0 ? `${h}h${m}m` : `${m}m`;
}

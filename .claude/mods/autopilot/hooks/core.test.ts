import { expect, test } from "claude-code/testing";
import {
  afterTurn,
  newState,
  parseCommand,
  requestStop,
  resume,
  setWait,
  stateKey,
  withDefaults,
} from "./core";

const HOUR = 3_600_000;
const base = () =>
  newState({
    sessionId: "s1",
    goal: "g",
    root: "/repo",
    now: 0,
    limits: withDefaults({ hours: 1, turns: 5, idle: 2 }),
  });

test("進捗があればターンを数えて次を起こす", async () => {
  const r = afterTurn(base(), "answer", 1000, "fp1");
  expect(r.action).toEqual({ kind: "wake", delayMs: 0 });
  expect(r.state.turns).toBe(1);
  expect(r.state.idleTurns).toBe(0);
});

test("進捗なしが上限に達したら止める", async () => {
  let s = afterTurn(base(), "answer", 1, "same").state;
  s = afterTurn(s, "answer", 2, "same").state;
  const r = afterTurn(s, "answer", 3, "same");
  expect(r.action.kind).toBe("stop");
  expect(r.state.status).toBe("stopped");
});

test("時間とターン数の上限で止める", async () => {
  expect(afterTurn(base(), "answer", HOUR, "x").action.kind).toBe("stop");
  const s = { ...base(), turns: 4 };
  expect(afterTurn(s, "answer", 1, "x").action.kind).toBe("stop");
});

test("Esc での中断は一時停止にする", async () => {
  const r = afterTurn(base(), "aborted", 1, "x");
  expect(r.action.kind).toBe("pause");
  expect(r.state.status).toBe("paused");
});

test("API エラーは間隔を空けて起こし、3 回続いたら一時停止", async () => {
  let r = afterTurn(base(), "error", 1, "x");
  expect(r.action).toEqual({ kind: "wake", delayMs: 30_000 });
  r = afterTurn(r.state, "error", 2, "x");
  r = afterTurn(r.state, "error", 3, "x");
  expect(r.action.kind).toBe("pause");
});

test("待機中は起こさず、進捗なしにも数えない", async () => {
  const s = setWait({ ...base(), fingerprint: "same" }, 0, 10, "CI");
  const r = afterTurn(s, "answer", 1000, "same");
  expect(r.action).toEqual({ kind: "wait", untilMs: 600_000 });
  expect(r.state.idleTurns).toBe(0);
  const after = afterTurn(r.state, "answer", 700_000, "next");
  expect(after.action.kind).toBe("wake");
  expect(after.state.waitUntil).toBe(undefined);
});

test("停止要求は 1 回目を差し戻し、進捗が出たら数え直す", async () => {
  const first = requestStop(base(), 1);
  expect(first.accepted).toBe(false);
  expect(requestStop(first.state, 2).accepted).toBe(true);
  const progressed = afterTurn(first.state, "answer", 3, "new").state;
  expect(requestStop(progressed, 4).accepted).toBe(false);
});

test("再開は期限切れなら時間とターンを延長する", async () => {
  const s = { ...base(), status: "paused" as const, turns: 5 };
  const r = resume(s, { sessionId: "s2", now: 2 * HOUR, limits: {} });
  expect(r.status).toBe("running");
  expect(r.sessionId).toBe("s2");
  expect(r.deadlineAt > 2 * HOUR).toBe(true);
  expect(r.maxTurns > 5).toBe(true);
});

test("引数を解析する", async () => {
  expect(parseCommand("")).toEqual({ kind: "status" });
  expect(parseCommand("pause")).toEqual({ kind: "pause" });
  expect(parseCommand("start --hours 2 テストを直す")).toEqual({
    kind: "start",
    goal: "テストを直す",
    limits: { hours: 2 },
  });
  expect(parseCommand("README を整える --turns=50")).toEqual({
    kind: "start",
    goal: "README を整える",
    limits: { turns: 50 },
  });
  expect(parseCommand("resume --hours 1")).toEqual({
    kind: "resume",
    limits: { hours: 1 },
  });
  expect(parseCommand("start").kind).toBe("error");
});

test("状態キーは bash の置換と同じ形になる", async () => {
  expect(stateKey("/Users/a/my repo")).toBe("-Users-a-my-repo");
});

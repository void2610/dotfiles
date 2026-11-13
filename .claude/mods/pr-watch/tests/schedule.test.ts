import assert from "node:assert/strict";
import { test } from "node:test";
import {
  afterFailure,
  afterSuccess,
  due,
  forced,
  initialSchedule,
} from "../hooks/schedule.ts";

const now = 1_000_000;

test("起動直後はすぐ取りに行く", () => {
  assert.equal(due(initialSchedule, now), true);
});

test("取れたら 60 秒は取り直さない", () => {
  const s = afterSuccess(initialSchedule, now);
  assert.equal(due(s, now + 59_999), false);
  assert.equal(due(s, now + 60_000), true);
});

test("失敗が続くと 60 秒から倍々に空け、15 分で頭打ちにする", () => {
  let s = initialSchedule;
  const waits: number[] = [];
  for (let i = 0; i < 6; i++) {
    s = afterFailure(s, now, false);
    waits.push(s.nextGhAt - now);
  }
  assert.deepEqual(
    waits,
    [60_000, 120_000, 240_000, 480_000, 900_000, 900_000],
  );
});

test("API の上限に当たったら 10 分空ける", () => {
  const s = afterFailure(initialSchedule, now, true);
  assert.equal(s.nextGhAt - now, 600_000);
});

test("取れたら失敗の空け幅を戻す", () => {
  const failed = afterFailure(
    afterFailure(initialSchedule, now, false),
    now,
    false,
  );
  const s = afterFailure(afterSuccess(failed, now), now, false);
  assert.equal(s.nextGhAt - now, 60_000);
});

test("明示の取り直しは待ちを捨てる", () => {
  const s = forced(afterFailure(initialSchedule, now, true));
  assert.equal(due(s, now), true);
});

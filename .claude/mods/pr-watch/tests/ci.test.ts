import assert from "node:assert/strict";
import { test } from "node:test";
import { ciSummaryOf } from "../hooks/ci.ts";

test("チェックを見たことの無い PR の 0 件は CI なしとして扱う", () => {
  assert.equal(ciSummaryOf([], false).state, "none");
});

test("チェックを見た後の 0 件は push 直後の未登録として待つ", () => {
  assert.equal(ciSummaryOf([], true).state, "pending");
});

test("走っているチェックがあれば待ち、すべて成功なら成功", () => {
  assert.equal(ciSummaryOf([{ conclusion: "SUCCESS" }, { status: "QUEUED" }], true).state, "pending");
  assert.equal(ciSummaryOf([{ conclusion: "SUCCESS" }], true).state, "pass");
});

test("失敗が 1 つでもあれば失敗", () => {
  assert.equal(ciSummaryOf([{ conclusion: "SUCCESS" }, { conclusion: "FAILURE" }], true).state, "fail");
});

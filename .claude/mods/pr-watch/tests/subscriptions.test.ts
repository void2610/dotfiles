import assert from "node:assert/strict";
import { test } from "node:test";
import {
  closedNotice,
  deferred,
  dueOthers,
  OTHER_BRANCH_INTERVAL_MS,
  subscribe,
  unsubscribe,
} from "../hooks/subscriptions.ts";

const url = "https://github.com/o/r/pull/353";
const now = 1_000_000;

test("同じ PR は二重に購読しない", () => {
  const subs = subscribe(subscribe([], 353, url), 353, url);
  assert.equal(subs.length, 1);
});

test("今いるブランチの PR は他ブランチの確認対象に入れない", () => {
  const subs = subscribe(subscribe([], 353, url), 354, url);
  assert.deepEqual(
    dueOthers(subs, 353, now).map((s) => s.number),
    [354],
  );
});

test("ブランチを離れた PR (今いるブランチに PR が無い) も追い続ける", () => {
  const subs = subscribe([], 353, url);
  assert.deepEqual(
    dueOthers(subs, undefined, now).map((s) => s.number),
    [353],
  );
});

test("確認した PR は 5 分空けてから取り直す", () => {
  const subs = deferred(subscribe([], 353, url), 353, now);
  assert.equal(
    dueOthers(subs, undefined, now + OTHER_BRANCH_INTERVAL_MS - 1).length,
    0,
  );
  assert.equal(
    dueOthers(subs, undefined, now + OTHER_BRANCH_INTERVAL_MS).length,
    1,
  );
});

test("閉じた PR は購読から外す", () => {
  assert.equal(unsubscribe(subscribe([], 353, url), 353).length, 0);
});

test("マージとマージ無しのクローズで文面を分け、開いている PR では何も出さない", () => {
  assert.match(closedNotice(353, "MERGED") ?? "", /#353 がマージされた/);
  assert.match(closedNotice(353, "CLOSED") ?? "", /マージされずにクローズ/);
  assert.equal(closedNotice(353, "OPEN"), undefined);
});

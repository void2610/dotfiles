import assert from "node:assert/strict";
import { test } from "node:test";
import { closedNotice } from "../hooks/closed.ts";

test("開いているのを見た PR がマージされたら知らせる", () => {
  assert.match(
    closedNotice(353, "MERGED", true, false) ?? "",
    /#353 がマージされた/,
  );
});

test("マージされずに閉じたら別の文面で知らせる", () => {
  assert.match(
    closedNotice(353, "CLOSED", true, false) ?? "",
    /マージされずにクローズ/,
  );
});

test("知らせるのは一度だけ", () => {
  assert.equal(closedNotice(353, "MERGED", true, true), undefined);
});

test("開いているのを見ていない PR (前から閉じていたブランチ) では起こさない", () => {
  assert.equal(closedNotice(353, "MERGED", false, false), undefined);
});

test("開いている PR では何もしない", () => {
  assert.equal(closedNotice(353, "OPEN", true, false), undefined);
});

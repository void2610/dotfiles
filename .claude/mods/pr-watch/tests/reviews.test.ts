import assert from "node:assert/strict";
import { test } from "node:test";
import { countCopilotReviews, shouldWakeForUnable } from "../hooks/reviews.ts";

const copilot = { login: "copilot-pull-request-reviewer" };
const unable = {
  author: copilot,
  body: "Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.",
};
const reviewed = { author: copilot, body: "## Pull request overview" };

test("レビューできなかった旨だけのレビューはレビューに数えない", () => {
  assert.deepEqual(countCopilotReviews([unable]), { reviewed: 0, unable: 1 });
});

test("中身のあるレビューと人のレビューを分けて数える", () => {
  const human = { author: { login: "void2610" }, body: "LGTM" };
  assert.deepEqual(countCopilotReviews([unable, reviewed, human]), {
    reviewed: 1,
    unable: 1,
  });
});

test("CI が済んでレビューできなかっただけなら起こす", () => {
  assert.equal(shouldWakeForUnable(true, { reviewed: 0, unable: 1 }, undefined), true);
});

test("同じ状態では二度起こさない", () => {
  assert.equal(shouldWakeForUnable(true, { reviewed: 0, unable: 1 }, "1"), false);
});

test("依頼し直してまたレビューできなかったら、もう一度起こす", () => {
  assert.equal(shouldWakeForUnable(true, { reviewed: 0, unable: 2 }, "1"), true);
});

test("CI が終わっていない間は起こさない", () => {
  assert.equal(shouldWakeForUnable(false, { reviewed: 0, unable: 1 }, undefined), false);
});

test("中身のあるレビューが付いていれば、レビューできなかった件では起こさない", () => {
  assert.equal(shouldWakeForUnable(true, { reviewed: 1, unable: 1 }, undefined), false);
});

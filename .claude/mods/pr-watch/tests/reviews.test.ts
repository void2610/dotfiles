import assert from "node:assert/strict";
import { test } from "node:test";
import { countCopilotReviews, reviewSettled } from "../hooks/reviews.ts";

const copilot = { login: "copilot-pull-request-reviewer" };
const unable = {
  author: copilot,
  body: "Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.",
};
const reviewed = { author: copilot, body: "## Pull request overview" };

test("レビューできなかった旨だけのレビューは分けて数える", () => {
  assert.deepEqual(countCopilotReviews([unable]), { reviewed: 0, unable: 1 });
});

test("中身のあるレビューと人のレビューを分けて数える", () => {
  const human = { author: { login: "void2610" }, body: "LGTM" };
  assert.deepEqual(countCopilotReviews([unable, reviewed, human]), {
    reviewed: 1,
    unable: 1,
  });
});

test("レビューできなかった PR は片付いたものとして扱う", () => {
  assert.equal(reviewSettled({ reviewed: 0, unable: 1 }, undefined), true);
});

test("レビューがまだ届いていなければ片付いていない", () => {
  assert.equal(reviewSettled({ reviewed: 0, unable: 0 }, undefined), false);
});

test("レビューが付いたら未解決スレッドが無くなるまで片付いていない", () => {
  assert.equal(reviewSettled({ reviewed: 1, unable: 0 }, 2), false);
  assert.equal(reviewSettled({ reviewed: 1, unable: 0 }, 0), true);
});

test("レビューが付いていてスレッドの数が取れていなければ片付いていない", () => {
  assert.equal(reviewSettled({ reviewed: 1, unable: 1 }, undefined), false);
});

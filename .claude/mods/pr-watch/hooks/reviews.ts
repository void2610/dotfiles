export type Review = { author?: { login?: string }; body?: string };

export type CopilotReviews = {
  // 中身のあるレビューの数
  reviewed: number;
  // レビューできなかった旨だけを書いたレビューの数
  unable: number;
};

// 枠の不足などでレビューできなかったときも、Copilot は理由だけを書いたレビューを残す。スレッドは付かないので分けて数える
export function countCopilotReviews(
  reviews: readonly Review[],
): CopilotReviews {
  const copilot = reviews.filter((r) =>
    (r.author?.login ?? "").startsWith("copilot"),
  );
  const unable = copilot.filter((r) =>
    (r.body ?? "").startsWith("Copilot was unable to review"),
  ).length;
  return { reviewed: copilot.length - unable, unable };
}

// レビューが片付いたか。レビューできなかった PR は待っても付かないので、片付いたものとして先へ進める。
// unresolved は未解決スレッドの数 (取れていなければ undefined)
export function reviewSettled(
  counts: CopilotReviews,
  unresolved: number | undefined,
): boolean {
  if (counts.reviewed > 0) return unresolved === 0;
  return counts.unable > 0;
}

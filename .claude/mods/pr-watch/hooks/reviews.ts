export type Review = { author?: { login?: string }; body?: string };

export type CopilotReviews = {
  // 中身のあるレビューの数
  reviewed: number;
  // レビューできなかった旨だけを書いたレビューの数
  unable: number;
};

// 枠の不足などでレビューできなかったときも、Copilot は理由だけを書いたレビューを残す。これはレビューに数えない
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

// レビューできなかったのを「未解決スレッドが無い」と取り違えて先へ進めないよう、CI が済んだ時点で別の文で起こす。
// notified は前に起こしたときの unable の数。依頼し直してまたレビューできなかったら、もう一度起こす
export function shouldWakeForUnable(
  ciSettled: boolean,
  counts: CopilotReviews,
  notified: string | undefined,
): boolean {
  return (
    ciSettled &&
    counts.reviewed === 0 &&
    counts.unable > 0 &&
    notified !== String(counts.unable)
  );
}

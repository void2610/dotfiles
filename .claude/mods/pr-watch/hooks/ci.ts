export type CiState = "pass" | "fail" | "pending" | "none";

const RUNNING_STATES = ["", "PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED"];

/**
 * チェックの一覧を CI の状態にまとめる。
 * sawChecks は、この PR でチェックを一度でも見たか。見た後の 0 件は push 直後でまだ登録されていないだけなので、完了 (none) でなく待ち (pending) にする
 */
export function ciSummaryOf(
  rollup: readonly { state?: string; conclusion?: string; status?: string }[],
  sawChecks: boolean,
): { state: CiState; done: number; total: number } {
  const total = rollup.length;
  if (total === 0) return { state: sawChecks ? "pending" : "none", done: 0, total };
  const states = rollup.map((c) =>
    (c.conclusion || c.state || c.status || "").toUpperCase(),
  );
  const done = states.filter((s) => !RUNNING_STATES.includes(s)).length;
  if (
    states.some((s) => s === "FAILURE" || s === "ERROR" || s === "TIMED_OUT")
  ) {
    return { state: "fail", done, total };
  }
  if (done < total) return { state: "pending", done, total };
  return { state: "pass", done, total };
}

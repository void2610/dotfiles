// gh pr view は 1 回 GraphQL 1 ポイントだが、15 秒 × 複数セッションで上限 (5000/時) を実際に枯渇させたため 60 秒にする
export const MIN_GH_INTERVAL_MS = 60000;
const MAX_BACKOFF_MS = 900000;
const RATE_LIMIT_BACKOFF_MS = 600000;

export type Schedule = {
  nextGhAt: number;
  backoffMs: number;
};

export const initialSchedule: Schedule = { nextGhAt: 0, backoffMs: 0 };

export function due(s: Schedule, now: number): boolean {
  return now >= s.nextGhAt;
}

export function afterSuccess(s: Schedule, now: number): Schedule {
  return { ...s, nextGhAt: now + MIN_GH_INTERVAL_MS, backoffMs: 0 };
}

export function afterFailure(
  s: Schedule,
  now: number,
  rateLimited: boolean,
): Schedule {
  // 上限超過は分単位で回復しないため、通常の失敗より強く間隔を空ける。それ以外の失敗も多くは API 上限なので、間隔を広げて枯渇を助長しない
  const backoffMs = rateLimited
    ? RATE_LIMIT_BACKOFF_MS
    : Math.min(
        s.backoffMs ? s.backoffMs * 2 : MIN_GH_INTERVAL_MS,
        MAX_BACKOFF_MS,
      );
  return { ...s, nextGhAt: now + backoffMs, backoffMs };
}

// 明示操作 (/pr-watch・↻ ボタン) は間隔待ちを飛ばして即時取得する
export function forced(s: Schedule): Schedule {
  return { ...s, nextGhAt: 0 };
}

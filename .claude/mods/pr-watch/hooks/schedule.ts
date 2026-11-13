// gh pr view は 1 回 GraphQL 1 ポイントだが、15 秒 × 複数セッションで上限 (5000/時) を実際に枯渇させたため 60 秒にする
export const MIN_GH_INTERVAL_MS = 60000;
const MAX_BACKOFF_MS = 900000;
const RATE_LIMIT_BACKOFF_MS = 600000;

export type Schedule = {
  nextGhAt: number;
  backoffMs: number;
  // 直近に見た手元のブランチ・HEAD・upstream の組
  localKey?: string;
  // マージ・クローズ済みの PR は待っても変わらないので、手元が変わるか明示の取り直しまで止める
  parked?: boolean;
};

export const initialSchedule: Schedule = { nextGhAt: 0, backoffMs: 0 };

export function due(s: Schedule, now: number): boolean {
  return !s.parked && now >= s.nextGhAt;
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

// push・コミット・fetch で手元が変われば PR 側の CI やレビューも動き出すので、間隔もバックオフも待たずに取り直す
export function observeLocal(s: Schedule, key: string): Schedule {
  if (key === s.localKey) return s;
  return { ...s, localKey: key, nextGhAt: 0, backoffMs: 0, parked: false };
}

export function park(s: Schedule): Schedule {
  return { ...s, parked: true };
}

// 明示操作 (/pr-watch・↻ ボタン) は間隔待ちを飛ばして即時取得する
export function forced(s: Schedule): Schedule {
  return { ...s, nextGhAt: 0, parked: false };
}

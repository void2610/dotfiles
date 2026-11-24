// セッションが開いた PR を、ブランチを移っても追い続けるための購読一覧 (公式のクラウド環境の PR 購読と同じく、PR 単位で持つ)
export type Sub = { number: number; url: string; nextAt: number };

// 今いるブランチ以外の PR で次に動くのは人のレビューやマージなので、片付いた PR と同じ 5 分間隔にする
export const OTHER_BRANCH_INTERVAL_MS = 300000;

export function subscribe(
  subs: readonly Sub[],
  number: number,
  url: string,
): Sub[] {
  if (subs.some((s) => s.number === number)) return [...subs];
  return [...subs, { number, url, nextAt: 0 }];
}

export function unsubscribe(subs: readonly Sub[], number: number): Sub[] {
  return subs.filter((s) => s.number !== number);
}

export function dueOthers(
  subs: readonly Sub[],
  currentNumber: number | undefined,
  now: number,
): Sub[] {
  return subs.filter((s) => s.number !== currentNumber && now >= s.nextAt);
}

export function deferred(
  subs: readonly Sub[],
  number: number,
  now: number,
): Sub[] {
  return subs.map((s) =>
    s.number === number ? { ...s, nextAt: now + OTHER_BRANCH_INTERVAL_MS } : s,
  );
}

export function closedNotice(
  number: number,
  state: string,
): string | undefined {
  if (state === "MERGED") {
    return `PR #${number} がマージされた。デフォルトブランチへ戻って同期し、マージ済みのブランチと flow の状態を片付けよ。タスク管理や報告には、この PR をマージ済みとして書け。`;
  }
  if (state === "CLOSED") {
    return `PR #${number} がマージされずにクローズされた。gh pr view ${number} で経緯を確認し、タスク管理や報告には未マージのクローズとして書け。`;
  }
  return undefined;
}

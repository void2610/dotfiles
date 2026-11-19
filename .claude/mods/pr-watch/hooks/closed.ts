// マージ後もブランチや進捗の記録が開いたままの前提で進むのを防ぐ。前から閉じていたブランチを開き直しただけでは起こさない
export function closedNotice(
  prNumber: number,
  state: string,
  seenOpen: boolean,
  notified: boolean,
): string | undefined {
  if (!seenOpen || notified) return undefined;
  if (state === "MERGED") {
    return `PR #${prNumber} がマージされた。デフォルトブランチへ戻って同期し、マージ済みのブランチと ship の状態を片付けよ。タスク管理や報告には、この PR をマージ済みとして書け。`;
  }
  if (state === "CLOSED") {
    return `PR #${prNumber} がマージされずにクローズされた。gh pr view ${prNumber} で経緯を確認し、タスク管理や報告には未マージのクローズとして書け。`;
  }
  return undefined;
}

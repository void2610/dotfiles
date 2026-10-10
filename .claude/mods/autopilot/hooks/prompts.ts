import { type AutopilotState, formatRemaining } from "./core";

export const STATE_FILES = [
  "contract.md",
  "backlog.md",
  "decisions.md",
  "blocked.md",
  "log.md",
] as const;

export type StateFile = (typeof STATE_FILES)[number];

export function templates(s: AutopilotState): Record<StateFile, string> {
  const deadline = new Date(s.deadlineAt).toLocaleString("ja-JP");
  return {
    "contract.md": `# autopilot 契約

- 目標: ${s.goal}
- 触ってよい範囲: (着手前に記入)
- 完了の基準: (着手前に記入)
- 禁止事項: ゲームバランスや本番の挙動に効くデータの変更 / 取り消せない操作 (main への直接 push・削除・外部への投稿)
- 上限: ${deadline} まで / 最大 ${s.maxTurns} ターン / 進捗なし ${s.idleLimit} ターンで停止
`,
    "backlog.md":
      "# backlog\n\n<!-- - [ ] 項目 (出典: 目標 / issue #N / テスト失敗 など) -->\n",
    "decisions.md":
      "# 決定ログ\n\n<!-- ## 日時 問い / 採用した案 / 退けた案と理由 -->\n",
    "blocked.md":
      "# 人間待ち\n\n<!-- - [ ] 項目: 何が必要か / どこで止めたか -->\n",
    "log.md": "# 進捗ログ\n",
  };
}

const header = (s: AutopilotState, now: number) =>
  `[autopilot ${s.turns}/${s.maxTurns} ターン · 残り ${formatRemaining(s.deadlineAt - now)}]`;

export function kickoffPrompt(
  s: AutopilotState,
  dir: string,
  now: number,
): string {
  return `${header(s, now)} autopilot を開始した。目標: ${s.goal}

autopilot-playbook スキルを読み、状態ディレクトリ ${dir} の contract.md と backlog.md を目標とリポジトリの実態から自分で埋めてから、最初の項目に着手せよ。ユーザーへの確認は挟まない。`;
}

export function wakePrompt(
  s: AutopilotState,
  dir: string,
  now: number,
  note?: string,
): string {
  const idle =
    s.idleTurns > 0
      ? `\n直近 ${s.idleTurns} ターン進捗が無い (あと ${s.idleLimit - s.idleTurns} ターンで自動停止)。同じ項目に固執せず、別の項目か探索へ切り替えよ。`
      : "";
  const extra = note ? `\n${note}` : "";
  return `${header(s, now)} 続行。autopilot-playbook の手順で ${dir}/backlog.md の次の項目へ進め (空なら探索して追記)。確認待ちで止まらず、決定は decisions.md、人間が必要な作業は blocked.md に書いて別の項目へ。${idle}${extra}`;
}

export function compactInstructions(dir: string): string {
  return `autopilot 実行中。要約には、いま取り組んでいる backlog 項目・途中の検証・直近の決定を残すこと。全体の状態は ${dir} の contract.md / backlog.md / decisions.md / blocked.md / log.md にあり、圧縮後はそこを読み直して続ける。`;
}

export function statusText(
  s: AutopilotState | undefined,
  dir: string,
  now: number,
): string {
  if (!s) return "autopilot は動いていません (/autopilot start <目標> で開始)";
  const head =
    s.status === "running"
      ? "実行中"
      : s.status === "paused"
        ? "一時停止中 (/autopilot resume で再開)"
        : "停止済み";
  const lines = [
    `autopilot: ${head}`,
    `目標: ${s.goal}`,
    `ターン: ${s.turns}/${s.maxTurns} · 残り時間: ${formatRemaining(s.deadlineAt - now)} · 進捗なし: ${s.idleTurns}/${s.idleLimit}`,
  ];
  if (s.waitUntil !== undefined && s.waitUntil > now) {
    lines.push(
      `待機中: あと ${formatRemaining(s.waitUntil - now)} (${s.waitReason ?? ""})`,
    );
  }
  if (s.reason) lines.push(`理由: ${s.reason}`);
  lines.push(`状態: ${dir}`);
  return lines.join("\n");
}

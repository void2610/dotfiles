import type { Run } from "./caps";

const GH_STACK_RE = /stack|スタック|積み(上げ)?PR|多段 ?PR/i;

// モジュール環境はセッション中維持されるため、help 注入の一度きり判定に使える
let injected = false;

export async function ghStackHelpNote(
  run: Run,
  text: string,
): Promise<string | undefined> {
  if (injected || !GH_STACK_RE.test(text)) return undefined;
  const r = await run(["gh", "stack", "--help"]);
  if (r.exitCode !== 0) return undefined;
  injected = true;
  return `stacked PR 関連の依頼を検知した。この環境には gh の stack 拡張が導入済みである。stacked PR の作成・同期・再構成には手動の git 操作ではなく gh stack サブコマンドを優先して使うこと。以下は gh stack --help の出力:\n\n${r.stdout}`;
}

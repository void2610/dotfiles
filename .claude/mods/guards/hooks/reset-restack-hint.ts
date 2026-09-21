// reset 言及または積み直し系の語彙のいずれかで発火
const RESET_RESTACK_RE =
  /reset|リセット|積み直|積みなお|コミットし直|コミットしなお|切り直|作り直|やり直/i;
const MSG =
  "reset はユーザーが既に完了しており、Claude が破壊的操作 (git reset 等) を実行する必要は無い。「権限上できない」等と拒否せず、まず git status / git log / git reflog で現状を確認し、作業ツリーの内容からコミットを積み直せ。";

export const resetRestackNote = (text: string): string | undefined =>
  RESET_RESTACK_RE.test(text) ? MSG : undefined;

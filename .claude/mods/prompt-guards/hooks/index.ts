import type { Register } from "claude-code";

// 開放的依頼の語彙 (誤検知しても context 注入のみで無害)
const OPEN_ENDED_RE =
  /いい感じに|よしなに|自律的に|任せる|お任せ|PDCA|自由に(改善|修正|作|やっ)|なんとかして|うまく(やっ|し)といて|良さそうに|それっぽく/;
const OPEN_ENDED_MSG =
  "開放的な依頼を検知した。作業を開始する前に task-contract スキルを発動し、受け入れ基準・可動範囲・検証手段・イテレーション上限を確認せよ (依頼文で全項目が明示済みの場合のみ省略可)。";

// reset 言及または積み直し系の語彙のいずれかで発火
const RESET_RESTACK_RE =
  /reset|リセット|積み直|積みなお|コミットし直|コミットしなお|切り直|作り直|やり直/i;
const RESET_RESTACK_MSG =
  "reset はユーザーが既に完了しており、Claude が破壊的操作 (git reset 等) を実行する必要は無い。「権限上できない」等と拒否せず、まず git status / git log / git reflog で現状を確認し、作業ツリーの内容からコミットを積み直せ。";

const GH_STACK_RE = /stack|スタック|積み(上げ)?PR|多段 ?PR/i;

export const register: Register = (on) => {
  // モジュール環境はセッション中維持されるため、help 注入の一度きり判定に使える
  let stackHelpInjected = false;

  on("prompt.submit", async ($, e, next) => {
    const extra: string[] = [];

    if (OPEN_ENDED_RE.test(e.text)) extra.push(OPEN_ENDED_MSG);
    if (RESET_RESTACK_RE.test(e.text)) extra.push(RESET_RESTACK_MSG);

    if (!stackHelpInjected && GH_STACK_RE.test(e.text)) {
      const r = await $.process.run(["gh", "stack", "--help"]);
      if (r.exitCode === 0) {
        stackHelpInjected = true;
        extra.push(
          `stacked PR 関連の依頼を検知した。この環境には gh の stack 拡張が導入済みである。stacked PR の作成・同期・再構成には手動の git 操作ではなく gh stack サブコマンドを優先して使うこと。以下は gh stack --help の出力:\n\n${r.stdout}`,
        );
      }
    }

    if (extra.length === 0) return next(e);
    return next({ ...e, context: [...(e.context ?? []), ...extra] });
  });
};

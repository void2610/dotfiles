// 開放的依頼の語彙 (誤検知しても context 注入のみで無害)
const OPEN_ENDED_RE =
  /いい感じに|よしなに|自律的に|任せる|お任せ|PDCA|自由に(改善|修正|作|やっ)|なんとかして|うまく(やっ|し)といて|良さそうに|それっぽく/;
const MSG =
  "開放的な依頼を検知した。作業を開始する前に task-contract スキルを発動し、受け入れ基準・可動範囲・検証手段・イテレーション上限を確認せよ (依頼文で全項目が明示済みの場合のみ省略可)。";

export const taskContractNote = (text: string): string | undefined =>
  OPEN_ENDED_RE.test(text) ? MSG : undefined;

// ビルドと送信は、人がその回の入力で頼んだときだけ許す。頼まれていないのに「最新を入れておこう」と自分の判断で回し、ビルドが何本も届いた (particle-culture)
const BUILD_RE =
  /MacBuild\.Build\w*\s*\(|BuildPipeline\.BuildPlayer|-executeMethod\s+\S*Build/;
const SEND_RE = /tailscale\s+file\s+cp\b/;
const REQUEST_RE = /ビルド|build|送って|送れ|送信して/i;
// 質問 (文末の ？) と、ビルドを止める言い方は頼みに数えない
const NOT_REQUEST_RE =
  /[?？]\s*$|ビルド(する|し)な|ビルドすんな|勝手に.{0,6}ビルド|ビルド.{0,4}(しない|不要|いらない)/i;
const HUMAN_ORIGINS = new Set(["composer", "bridge", "sdk", "slack-ping"]);

export type BuildPermit = { asked: boolean; built: boolean };

export const isBuildRequest = (text: string): boolean =>
  REQUEST_RE.test(text) && !NOT_REQUEST_RE.test(text);

// 人の入力が来るたびに許可を作り直す。人以外の投入 (停止フックの差し戻し・通知) では変えない
export const nextPermit = (
  permit: BuildPermit,
  text: string,
  originKind: string,
): BuildPermit =>
  HUMAN_ORIGINS.has(originKind)
    ? { asked: isBuildRequest(text), built: false }
    : permit;

export const buildDeny = (
  command: string,
  permit: BuildPermit,
): string | undefined => {
  const building = BUILD_RE.test(command);
  const sending = SEND_RE.test(command);
  if (!building && !sending) return undefined;
  if (!permit.asked)
    return "ビルドと送信は、ユーザーがその回の入力で頼んだときだけ行う (頼まれていない)。変更は push までにし、ビルドは頼まれてから行う。";
  if (building && permit.built)
    return "この依頼でのビルドは済んでいる。同じ依頼のうちに作り直さない。作り直しが要るなら、理由を書いてユーザーに頼んでもらう。";
  return undefined;
};

export const isBuildCommand = (command: string): boolean =>
  BUILD_RE.test(command);

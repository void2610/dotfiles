import type { Register } from "claude-code";

const ARCHIVE_DIR = "~/Documents/claude-artifacts";

// scratchpad (/private)/tmp 配下は セッション終了で消えるため配信元にさせない
const EPHEMERAL = /^\/(private\/)?(tmp|var\/folders)\//;

type ArtifactArgs = { action?: string; file_path?: string; asset?: boolean };

export const register: Register = (on) => {
  // 生成型の tool union に Artifact が無いため RegExp matcher で束縛する
  on("tool.call", { tool: /^Artifact$/ }, (_$, e, next) => {
    const args = e as unknown as ArtifactArgs;
    const isPublish = (args.action ?? "publish") === "publish" && !args.asset;
    if (isPublish && args.file_path && EPHEMERAL.test(args.file_path)) {
      return {
        deny: `一時ディレクトリからの publish は禁止。ファイルを ${ARCHIVE_DIR}/ へ内容が分かる kebab-case 名で保存し直し、そこから publish し直すこと (セッション終了後もソースを残すため)。`,
      };
    }
    return next(e);
  });
};

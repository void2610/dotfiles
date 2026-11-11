import type { Register } from "claude-code";

const ARCHIVE_DIR = "~/Documents/claude-artifacts";

// scratchpad (/private)/tmp 配下は セッション終了で消えるため配信元にさせない
const EPHEMERAL = /^\/(private\/)?(tmp|var\/folders)\//;

// explain-diff-html の解説ページの名前 (YYYY-MM-DD-explanation-<slug>.html)
const EXPLANATION = /explanation[^/\s'"]*\.html$/;
const EPHEMERAL_EXPLANATION_IN_COMMAND =
  /(^|[\s'"=])\/(private\/)?(tmp|var\/folders)\/[^\s'"]*explanation[^\s'"]*\.html/;
const EXPLANATION_DENY = `解説ページを一時ディレクトリに置くのは禁止。${ARCHIVE_DIR}/YYYY-MM-DD-explanation-<slug>.html に書き直すこと (泉 2026-10-30・11-11。/tmp は消えて読み返せない)。`;

type ArtifactArgs = { action?: string; file_path?: string; asset?: boolean };

export const register: Register = (on) => {
  on("tool.call", { tool: "Write" }, (_$, e, next) => {
    if (EPHEMERAL.test(e.file_path) && EXPLANATION.test(e.file_path))
      return { deny: EXPLANATION_DENY };
    return next(e);
  });

  on("tool.call", { tool: "Bash" }, (_$, e, next) => {
    // 一時ディレクトリから正しい置き場へ移すコマンドは通す
    if (
      EPHEMERAL_EXPLANATION_IN_COMMAND.test(e.command) &&
      !e.command.includes("claude-artifacts")
    )
      return { deny: EXPLANATION_DENY };
    return next(e);
  });

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

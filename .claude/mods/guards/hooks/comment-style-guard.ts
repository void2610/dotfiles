import type { Run } from "./caps";

const MARKERS: readonly [RegExp, string][] = [
  [
    /\.(sh|bash|zsh|py|rb|pl|nix|toml|yml|yaml|conf|tf|fish|mk)$|(^|\/)Makefile$/,
    "#",
  ],
  [
    /\.(c|h|cpp|hpp|cc|cs|m|mm|swift|js|jsx|ts|tsx|go|rs|java|kt|kts|scala|dart|zig)$/,
    "//",
  ],
  [/\.(lua|hs|sql|elm)$/, "--"],
  [/\.vim$|vimrc$/, '"'],
  [/\.(el|lisp|clj)$/, ";"],
];

const MSG = (path: string, found: string) =>
  `CLAUDE.md の Comments ルール違反の可能性: ${path} に複数行コメントブロックが追加された。
以下のワークフローを今回の Edit 1 回で完結させる (段階的な削減はしない):

1. コメントが WHY (非自明な理由: workaround・制約・ドメイン知識) / Why not (採らなかった選択肢とその理由) を述べているか確認する
2. 述べていない → 削除する
   - what コメント (次の行が何をするかの言い換え) — What の説明はテストコードの責務
   - Usage・列挙
   - 変更過程の説明 (fixed / changed 等)
3. 述べている → 1 行に削減する
   - 要約不能な複雑な制約/ドメイン知識のみ、そのまま残して再編集しない

事実として正しい既存コメントは保持する。

## 検出ブロック
${found}`;

// 2行以上連続するフルラインコメントブロックを抽出 (shebang・@ディレクティブ行は除外)
function extractBlocks(text: string, m: string, dm: string): string[] {
  const blocks: string[] = [];
  let buf: string[] = [];
  const flush = () => {
    if (buf.length >= 2) blocks.push(buf.join("\n"));
    buf = [];
  };
  for (const line of text.split("\n")) {
    const l = line.replace(/^[ \t]+/, "");
    if (
      l.startsWith(m) &&
      !l.startsWith("#!") &&
      (dm === "" || !l.startsWith(dm))
    ) {
      let r = l.slice(m.length);
      r = r.replace(/^[-!/*#";]*[ \t]*/, "");
      // awk の next 相当: @行は flush せず読み飛ばす (既存ブロックの非連続化と対で old 側の抽出結果比較が必要)
      if (r.startsWith("@")) continue;
      buf.push(line);
    } else flush();
  }
  flush();
  return blocks;
}

export async function commentStyleNote(
  run: Run,
  path: string,
  newText: string,
  oldText: string,
  isWrite: boolean,
): Promise<string | undefined> {
  const marker = MARKERS.find(([re]) => re.test(path))?.[1];
  if (!marker) return undefined;
  // doc コメント (C#/Rust の ///) はブロック検知から除外
  const dm = marker === "//" ? "///" : "";

  // Write (old_string なし) は git HEAD の内容を既存扱いにする
  let old = oldText;
  if (isWrite) {
    const dir = path.replace(/\/[^/]+$/, "");
    const rel = await run([
      "git",
      "-C",
      dir,
      "ls-files",
      "--full-name",
      "--",
      path,
    ]);
    const relPath = rel.stdout.trim().split("\n")[0];
    if (rel.exitCode === 0 && relPath) {
      const show = await run(["git", "-C", dir, "show", `HEAD:${relPath}`]);
      if (show.exitCode === 0) old = show.stdout;
    }
  }

  const blocks = extractBlocks(newText, marker, dm);
  if (blocks.length === 0) return undefined;
  // @行を挟む既存ブロックは抽出結果が非連続になり raw 比較で一致しないため、old 側の抽出結果とも比較する
  const oldBlocks = extractBlocks(old, marker, dm).join("\n");

  const found = blocks
    .filter((b) => !old.includes(b) && !oldBlocks.includes(b))
    .map((b) => `${b}\n----`)
    .join("\n");
  return found ? MSG(path, found) : undefined;
}

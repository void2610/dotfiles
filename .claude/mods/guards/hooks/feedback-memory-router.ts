import type { ReadFile } from "./caps";

const MSG = `feedback メモリが保存された。この指導の適用スコープを判定し、正しい階層へ配置し直せ:
1. 全プロジェクト普遍 → 決定論化できるなら hook 化をユーザーに提案。できなければ ~/.claude/CLAUDE.md へ昇格し、メモリは削除
2. リポジトリ普遍 → repo の CLAUDE.md / .claude/skills へ (git 同期で全 worktree に届き、乖離が構造的に消える)。メモリは削除
3. このリポジトリの一時的・作業固有の知識 → メモリのままでよい。ただし陳腐化条件 (何が完了したら消すか) を本文に明記せよ`;

export async function feedbackMemoryNote(
  readFile: ReadFile,
  path: string,
): Promise<string | undefined> {
  if (!/\/\.claude\/projects\/[^/]+\/memory\/[^/]+\.md$/.test(path))
    return undefined;
  try {
    const text = await readFile(path);
    if (/^\s*type:\s*feedback/m.test(text)) return MSG;
  } catch {
    return undefined;
  }
  return undefined;
}

// $.tool.register のツールは本体が MCP サーバーを組み直すと外れ、登録し直すまで戻らない

/** 登録したはずなのに一覧 (mcp__flow-hud__<name>) に無いツールの名前 */
export function missingTools(
  listed: readonly string[],
  specNames: readonly string[],
): string[] {
  const have = new Set(listed);
  return specNames.filter((name) => !have.has(`mcp__flow-hud__${name}`));
}

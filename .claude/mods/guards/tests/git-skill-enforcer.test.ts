import assert from "node:assert/strict";
import { test } from "node:test";
import { gitSkillDeny } from "../hooks/git-skill-enforcer.ts";

test("スキルを通さない git push と git commit は止める", () => {
  assert.ok(gitSkillDeny("git push"));
  assert.ok(gitSkillDeny("cd repo && git commit -m x"));
});

test("スキルの印が付いていれば通す", () => {
  assert.equal(gitSkillDeny("CLAUDE_GIT_SKILL=commit git commit -m x"), undefined);
});

test("ヒアドキュメントの本文に書いた git push は止めない", () => {
  const cmd = "cat > article.md <<'EOF'\n手順:\ngit push origin main\nEOF";
  assert.equal(gitSkillDeny(cmd), undefined);
});

test("ヒアドキュメントの後に続く git push は止める", () => {
  assert.ok(gitSkillDeny("cat > a.md <<EOF\nbody\nEOF\ngit push"));
  assert.ok(gitSkillDeny("cat > a.md <<'EOF' && git push\nbody\nEOF"));
});

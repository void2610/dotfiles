import assert from "node:assert/strict";
import { test } from "node:test";
import { buildDeny, isBuildRequest, nextPermit } from "../hooks/build-guard.ts";

const BUILD = `uloop execute-dynamic-code --code 'return ParticleCulture.Editor.MacBuild.Build();'`;
const SEND = "timeout 200 tailscale file cp --verbose a.zip shuyamacbook-pro:";

test("ビルド・送信の依頼を拾い、質問と止める言い方は拾わない", () => {
  assert.equal(isBuildRequest("ビルド"), true);
  assert.equal(isBuildRequest("終わったらビルド"), true);
  assert.equal(isBuildRequest("MacBook に送って"), true);
  assert.equal(isBuildRequest("ビルドした？"), false);
  assert.equal(isBuildRequest("勝手にビルドすんな"), false);
  assert.equal(isBuildRequest("水面の波が荒ぶる"), false);
});

test("頼まれていないビルドと送信は止め、ほかのコマンドは通す", () => {
  const permit = nextPermit(
    { asked: false, built: false },
    "波紋を直して",
    "composer",
  );
  assert.notEqual(buildDeny(BUILD, permit), undefined);
  assert.notEqual(buildDeny(SEND, permit), undefined);
  assert.equal(buildDeny("uloop compile", permit), undefined);
});

test("頼まれたらビルドを 1 回と送信を通し、2 回目のビルドは止める", () => {
  const permit = nextPermit(
    { asked: false, built: false },
    "ビルド",
    "composer",
  );
  assert.equal(buildDeny(BUILD, permit), undefined);
  const after = { ...permit, built: true };
  assert.notEqual(buildDeny(BUILD, after), undefined);
  assert.equal(buildDeny(SEND, after), undefined);
});

test("人以外の投入 (停止フックの差し戻し等) では許可を変えない", () => {
  const asked = nextPermit(
    { asked: false, built: false },
    "ビルド",
    "composer",
  );
  assert.deepEqual(nextPermit(asked, "絶対に止まるな", "hook"), asked);
  const idle = nextPermit(asked, "波紋を直して", "composer");
  assert.equal(idle.asked, false);
});

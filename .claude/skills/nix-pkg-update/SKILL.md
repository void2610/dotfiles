---
name: nix-pkg-update
description: "Update a custom npm package managed in /Users/shuya/nix-config/pkgs/ to the latest version. Edits the .nix file with the new version and hash, then rebuilds with darwin-rebuild."
---

# nix-pkg-update

`/Users/shuya/nix-config/pkgs/` で管理されているカスタム npm パッケージを最新バージョンに更新する。

## 対象パッケージ

`pkgs/` にある `.nix` ファイルが対象：
- `uloop-cli.nix` → npm パッケージ `uloop-cli`
- `claude-code-ui.nix` → npm パッケージ `@siteboon/claude-code-ui`

## 手順

### 1. 更新対象を特定する

引数でパッケージ名が指定された場合はそれを使う。指定がなければ `pkgs/*.nix` を列挙してユーザーに確認する。

```bash
ls /Users/shuya/nix-config/pkgs/*.nix
```

対応する `.nix` ファイルを開き、現在の `version` と npm パッケージ名（`pname` または URL から判断）を確認する。

### 2. 現在と最新のバージョンを比較

```bash
# 現在のバージョン（.nix ファイルから）
grep 'version = ' /Users/shuya/nix-config/pkgs/<パッケージ名>.nix

# npm の最新バージョン
npm info <npm-package-name> version
```

最新バージョンが現在と同じなら「すでに最新です」と伝えて終了する。

### 3. このマシンの flake target を特定する

**重要**: flake の構成名（target）は実ホスト名と異なる。`darwinConfigurations` のキーは
`game` / `work` / `server` で、`nix-darwin/hosts/default.nix` が hostName → target を対応づける。
ビルド／適用コマンドはこの target を使う（`Macintosh` 等のホスト名ではない）。

```bash
scutil --get LocalHostName   # 例: Macintosh
```

`nix-darwin/hosts/default.nix` の `hostName` が一致するキーが target：

| hostName | flake target |
|---|---|
| `Macintosh` | `game` |
| `PCmac24055` | `work` |
| `m1server` | `server` |

以降の例では `<target>` を特定した値（例: `game`）に置き換える。

### 4. 新バージョンの src ハッシュを取得する

tarball を直接 prefetch して SRI ハッシュを得る（仮ハッシュ→ビルドエラー方式より確実。
SRI の長さ不一致で `got:` 行が出ないことがあるため）。

```bash
nix store prefetch-file --json --hash-type sha512 \
  "https://registry.npmjs.org/<npm-package-name>/-/<basename>-<新バージョン>.tgz" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])"
```

- `<basename>` はスコープを除いた名前（`@siteboon/claude-code-ui` → `claude-code-ui`）。
- `--hash-type` は `.nix` の `hash` 接頭辞に合わせる（`sha512-` なら sha512、`sha256-` なら sha256）。

### 5. .nix ファイルを更新する

`version` を新バージョンに、`hash`（src）を手順4で得た値に書き換える。

`buildNpmPackage` パターン（`npmDepsHash` あり）は npm 依存ツリーのハッシュなので prefetch では取れない。
`npmDepsHash` を `pkgs.lib.fakeHash`（`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=`、正しい長さ）に
置いてビルドし、エラーの `got:` 行から正値を取得して再更新する。

### 6. ビルド確認

```bash
cd /Users/shuya/nix-config
git add pkgs/<パッケージ名>.nix
nix build .#darwinConfigurations.<target>.system --no-link
```

成功することを確認する。

### 7. 適用

`darwin-rebuild switch` は sudo パスワードを要求する。スキル実行環境では非対話 sudo が通らないことが多いので、
その場合はユーザーに `! cd /Users/shuya/nix-config && sudo darwin-rebuild switch --flake .#<target>` の実行を依頼する。

```bash
cd /Users/shuya/nix-config && sudo darwin-rebuild switch --flake .#<target>
```

### 8. 動作確認

インストールされたコマンドでバージョンを確認する（例：`uloop --version`、`claude-code-ui --version`）。

### 9. コミット

```bash
git add pkgs/<パッケージ名>.nix
git commit -m "Update <パッケージ名> to <新バージョン>"
```

## 補足

### .nix ファイルの構造パターン

**stdenv.mkDerivation パターン**（self-contained バンドル向け、例: uloop-cli）:
```nix
version = "1.6.3";
src = pkgs.fetchurl {
  url = "https://registry.npmjs.org/uloop-cli/-/uloop-cli-${version}.tgz";
  hash = "sha512-...";  # ← prefetch で取得（手順4）
};
```

**buildNpmPackage パターン**（npm依存あり、例: claude-code-ui）:
```nix
version = "1.27.1";
src = pkgs.fetchurl {
  url = "...${version}.tgz";
  hash = "sha512-...";       # ← src は prefetch で取得（手順4）
};
npmDepsHash = "sha256-...";  # ← prefetch 不可。fakeHash → ビルドエラーの got: で取得（手順5）
```

### nix-config のリポジトリ

`/Users/shuya/nix-config`
</content>
</invoke>

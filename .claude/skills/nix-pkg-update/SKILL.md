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

### 3. 新バージョンの tarball ハッシュを取得

`.nix` ファイルの `version` を新バージョンに、`hash` を仮値に書き換えてビルドし、エラーから正しいハッシュを取得する：

```bash
# .nix ファイルを編集（version を新バージョンに、hash を仮値に）
# hash = "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

cd /Users/shuya/nix-config
git add pkgs/<パッケージ名>.nix
nix build .#darwinConfigurations.Macintosh.system --no-link 2>&1 | grep "got:"
```

エラー出力の `got:` 行から正しいハッシュを取得する。

### 4. .nix ファイルを正しい値で更新

`version` と `hash` の両方を正しい値に更新する。

### 5. ビルド確認

```bash
git add pkgs/<パッケージ名>.nix
nix build .#darwinConfigurations.Macintosh.system --no-link
```

成功することを確認する。

### 6. 適用

```bash
sudo darwin-rebuild switch --flake .#Macintosh
```

### 7. 動作確認

インストールされたコマンドでバージョンを確認する（例：`uloop --version`、`claude-code-ui --version`）。

### 8. コミット

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
  hash = "sha512-...";  # ← ここを更新
};
```

**buildNpmPackage パターン**（npm依存あり、例: claude-code-ui）:
```nix
version = "1.27.1";
src = pkgs.fetchurl {
  url = "...${version}.tgz";
  hash = "sha512-...";       # ← src のハッシュを更新
};
npmDepsHash = "sha256-...";  # ← npm deps のハッシュも更新が必要
```

`buildNpmPackage` の場合は `npmDepsHash` も仮値にしてハッシュを2回取得する：
1. `hash`（src）のハッシュエラー → 修正
2. `npmDepsHash` のハッシュエラー → 修正
3. 再ビルドで成功を確認

### nix-config のリポジトリ

`/Users/shuya/nix-config`

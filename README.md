# dotfiles

個人用のdotfiles設定リポジトリです。
パッケージ管理と Homebrew 管理は別の `nix-config` リポジトリで行い、このリポジトリは主にシェルやアプリ設定を管理します。

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 2. Nix / nix-darwin 設定の適用

```bash
cd ~/nix-config
darwin-rebuild switch --flake .#<nix-configで定義したホスト名>
```

### 3. dotfilesのシンボリックリンク作成

```bash
./install.sh
```

既存の設定ファイルは`~/backup`ディレクトリにバックアップされます。

## ファイル構成

- `install.sh`: dotfilesのシンボリックリンク作成スクリプト
- `MANUAL_APPS.md`: 手動インストールが必要なアプリケーション一覧
- `.config/`: 各種アプリケーションの設定ファイル
- `.zshrc`: Zshシェルの設定
- `.gitconfig`: Git設定
- `.tmux.conf`: tmux設定
- `.claude/`: Claude Code の設定
- `.codex/`: Codex の設定

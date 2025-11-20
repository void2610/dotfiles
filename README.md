# dotfiles

個人用のdotfiles設定リポジトリです。

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 2. Homebrewのインストール（未インストールの場合）

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Homebrew パッケージのインストール

`brew-setup.sh`を実行して、Brewfileに記載されたすべての依存関係をインストールします：

```bash
./brew-setup.sh
```

このスクリプトは以下を実行します：
- Homebrewがインストールされているか確認
- Brewfileの存在確認
- 未インストールのパッケージを自動インストール

### 4. dotfilesのシンボリックリンク作成

```bash
./install.sh
```

既存の設定ファイルは`~/backup`ディレクトリにバックアップされます。

## ファイル構成

- `Brewfile`: Homebrewでインストールするパッケージ一覧
- `brew-setup.sh`: Homebrewパッケージの自動インストールスクリプト
- `install.sh`: dotfilesのシンボリックリンク作成スクリプト
- `.config/`: 各種アプリケーションの設定ファイル
- `.zshrc`: Zshシェルの設定
- `.gitconfig`: Git設定
- `.tmux.conf`: tmux設定

## Brewfileの更新

新しいパッケージをインストールした後、Brewfileを更新する場合：

```bash
brew bundle dump --file=~/dotfiles/Brewfile --force
```

## トラブルシューティング

### Brewfileの内容確認

```bash
brew bundle check --file=~/dotfiles/Brewfile
```

### 未インストールのパッケージ一覧表示

```bash
brew bundle check --file=~/dotfiles/Brewfile --verbose
```
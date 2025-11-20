#!/bin/bash
set -e

# dotfilesディレクトリのパス（このスクリプトが置いてある場所）
DOTFILES_DIR="${HOME}/dotfiles"
# Brewfileのパス
BREWFILE="${DOTFILES_DIR}/Brewfile"

echo "=== Homebrew セットアップスクリプト ==="
echo ""

# Homebrewをインストール
echo "Homebrewをインストールしています..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# PATHを設定（Apple Silicon / Intel対応）
echo ""
echo "PATHを設定しています..."
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"

# Brewfileから依存関係をインストール
echo ""
echo "Brewfileから依存関係をインストールしています..."
brew bundle install --file="${BREWFILE}"

echo ""
echo "=== セットアップ完了 ==="

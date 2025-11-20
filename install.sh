#!/bin/bash
set -e

# dotfilesディレクトリのパス（このスクリプトが置いてある場所）
DOTFILES_DIR="${HOME}/dotfiles"
# バックアップ先ディレクトリのパス
BACKUP_DIR="${HOME}/backup"
# Brewfileのパス
BREWFILE="${DOTFILES_DIR}/Brewfile"

echo "=========================================="
echo "  dotfiles セットアップスクリプト"
echo "=========================================="
echo ""

# ========================================
# 1. Xcode Command Line Tools のインストール
# ========================================
echo "=== Xcode Command Line Tools のインストール ==="
xcode-select --install
echo "インストールダイアログが表示されたら、指示に従ってインストールしてください。"
echo "インストールが完了したら、Enterキーを押して続行してください..."
read
echo ""

# ========================================
# 2. Homebrew のインストール
# ========================================
echo "=== Homebrew のインストール ==="
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# PATHを設定（Apple Silicon / Intel対応）
echo "PATHを設定しています..."
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
echo ""

# ========================================
# 3. Brewfile からパッケージをインストール
# ========================================
echo "=== Brewfile からパッケージをインストール ==="
brew bundle install --file="${BREWFILE}"
echo ""

# ========================================
# 4. dotfiles のシンボリックリンク作成
# ========================================
echo "=== dotfiles のシンボリックリンク作成 ==="

# バックアップ先ディレクトリが存在しなければ作成
mkdir -p "${BACKUP_DIR}"

# シンボリックリンクを作成する対象のdotfilesリスト
FILES=(
  ".config"
  ".gitconfig"
  ".tmux.conf"
  ".zshrc"
  ".claude"
)

for file in "${FILES[@]}"; do
  TARGET="${HOME}/${file}"
  SOURCE="${DOTFILES_DIR}/${file}"

  # ホームディレクトリに同名のファイルまたはディレクトリが存在する場合、バックアップディレクトリに移動
  if [ -e "${TARGET}" ] || [ -L "${TARGET}" ]; then
    BACKUP_TARGET="${BACKUP_DIR}/${file}"
    if [ -e "${BACKUP_TARGET}" ]; then
      echo "既存の ${BACKUP_TARGET} を削除します..."
      rm -rf "${BACKUP_TARGET}"
    fi
    echo "既存の ${TARGET} を ${BACKUP_DIR} に移動します..."
    mv "${TARGET}" "${BACKUP_DIR}"
  fi

  # シンボリックリンクの作成
  echo "シンボリックリンクを作成: ${TARGET} -> ${SOURCE}"
  ln -s "${SOURCE}" "${TARGET}"
done

# ========================================
# セットアップ完了
# ========================================
echo "=========================================="
echo "  セットアップが完了しました！"
echo "=========================================="

#!/bin/bash
set -e

# dotfilesディレクトリのパス（このスクリプトが置いてある場所）
DOTFILES_DIR="${HOME}/dotfiles"
# バックアップ先ディレクトリのパス
BACKUP_DIR="${HOME}/backup"

echo "=========================================="
echo "  dotfiles シンボリックリンク作成"
echo "=========================================="
echo ""

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

echo ""
echo "✓ 全てのdotfilesのシンボリックリンクを作成しました"
echo ""

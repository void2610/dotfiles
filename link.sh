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
  ".claude"
  ".codex"
  ".markdownlint-cli2.jsonc"
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

# ホーム直下ではない深いパスへの個別シンボリックリンク。
# 書式: "<HOME からの相対 TARGET>:<dotfiles 内 SOURCE 相対パス>"
# macOS の lazygit は ~/Library/Application Support/lazygit/config.yml を読むので
# dotfiles の .config/lazygit/config.yml へリンクする。
NESTED_LINKS=(
  "Library/Application Support/lazygit/config.yml:.config/lazygit/config.yml"
)

for entry in "${NESTED_LINKS[@]}"; do
  REL_TARGET="${entry%%:*}"
  REL_SOURCE="${entry#*:}"
  TARGET="${HOME}/${REL_TARGET}"
  SOURCE="${DOTFILES_DIR}/${REL_SOURCE}"

  # 親ディレクトリを作成（"Library/Application Support/lazygit" など）
  mkdir -p "$(dirname "${TARGET}")"

  # 既存ファイルがあれば backup ディレクトリに退避（ファイル名衝突を防ぐためサニタイズ）
  if [ -e "${TARGET}" ] || [ -L "${TARGET}" ]; then
    SAFE_NAME="${REL_TARGET// /_}"
    SAFE_NAME="${SAFE_NAME//\//_}"
    BACKUP_TARGET="${BACKUP_DIR}/${SAFE_NAME}"
    if [ -e "${BACKUP_TARGET}" ]; then
      echo "既存の ${BACKUP_TARGET} を削除します..."
      rm -rf "${BACKUP_TARGET}"
    fi
    echo "既存の ${TARGET} を ${BACKUP_TARGET} に移動します..."
    mv "${TARGET}" "${BACKUP_TARGET}"
  fi

  echo "シンボリックリンクを作成: ${TARGET} -> ${SOURCE}"
  ln -s "${SOURCE}" "${TARGET}"
done

echo ""
echo "✓ 全てのdotfilesのシンボリックリンクを作成しました"
echo ""

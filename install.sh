#!/bin/bash
set -e

DOTFILES_DIR="${HOME}/dotfiles"
BACKUP_DIR="${HOME}/backup"
NIX_CONFIG_DIR="${HOME}/nix-config"

echo "=========================================="
echo "  dotfiles セットアップスクリプト"
echo "=========================================="
echo ""

echo "=========================================="
echo "ClaudeCode インストール"
echo "=========================================="
echo ""
curl -fsSL https://claude.ai/install.sh | bash

echo "=========================================="
echo "Nix インストール"
echo "=========================================="
echo ""
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# nix-config リポジトリのクローン（未クローンの場合のみ）
if [ ! -d "${NIX_CONFIG_DIR}" ]; then
  echo "nix-config をクローンします..."
  git clone "https://github.com/void2610/nix-config.git" "${NIX_CONFIG_DIR}"
else
  echo "nix-config は既にクローン済みです。スキップします。"
fi

# シンボリックリンク作成
"${DOTFILES_DIR}/link.sh"

echo "=========================================="
echo "  セットアップが完了しました！"
echo "=========================================="
echo ""
echo "次のコマンドで nix-darwin の設定を適用してください:"
echo "  cd ${NIX_CONFIG_DIR} && darwin-rebuild switch --flake .#<ホスト名>"

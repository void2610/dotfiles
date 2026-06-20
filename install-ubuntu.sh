#!/usr/bin/env bash
# Ubuntu 22.04 上で nvim (LazyVim) の依存ツールを揃えるセットアップスクリプト。
# 冪等に再実行できる。sudo は apt のみで使用する。
set -euo pipefail

LOCAL_BIN="${HOME}/.local/bin"
NVIM_DATA="${HOME}/.local/share/nvim"

log() { printf "\033[1;34m[setup]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 が見つかりません。先に導入してください。"
}

mkdir -p "${LOCAL_BIN}"

# ========================================
# 1. 前提コマンド確認
# ========================================
log "前提コマンドを確認"
require_cmd curl
require_cmd tar
require_cmd git
require_cmd nvim
require_cmd python3
require_cmd cargo  # rustup 経由で導入済みである前提
require_cmd gcc
require_cmd make

# ========================================
# 2. apt パッケージ
#    - libreadline-dev: hererocks の Lua 5.1 ビルドに必要
#    - libmagickwand-dev / imagemagick: image.nvim の magick rock 用
# ========================================
log "apt パッケージを導入"
APT_PKGS=(libreadline-dev libmagickwand-dev imagemagick build-essential)
MISSING_PKGS=()
for pkg in "${APT_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done
if (( ${#MISSING_PKGS[@]} > 0 )); then
  sudo apt update
  sudo apt install -y "${MISSING_PKGS[@]}"
else
  log "  全て導入済み"
fi

# ========================================
# 3. tree-sitter CLI
#    Mason 同梱版は GLIBC_2.39 を要求し Ubuntu 22.04 (2.35) で動かないため
#    cargo 版を入れ、Mason のシンボリックリンクを差し替える。
# ========================================
log "tree-sitter CLI を確認"
if ! command -v "${HOME}/.cargo/bin/tree-sitter" >/dev/null 2>&1; then
  log "  cargo install tree-sitter-cli"
  cargo install tree-sitter-cli --locked
else
  log "  cargo 版 tree-sitter は導入済み ($(${HOME}/.cargo/bin/tree-sitter --version))"
fi

MASON_TS="${NVIM_DATA}/mason/bin/tree-sitter"
if [[ -e "${MASON_TS}" ]] || [[ -L "${MASON_TS}" ]]; then
  current_target=$(readlink -f "${MASON_TS}" 2>/dev/null || true)
  expected_target=$(readlink -f "${HOME}/.cargo/bin/tree-sitter")
  if [[ "${current_target}" != "${expected_target}" ]]; then
    log "  Mason の tree-sitter シンボリックリンクを cargo 版へ差し替え"
    ln -sf "${HOME}/.cargo/bin/tree-sitter" "${MASON_TS}"
  else
    log "  Mason シンボリックリンクは正しく cargo 版を指している"
  fi
else
  warn "  Mason の tree-sitter が未配置。nvim 起動後に MasonInstall tree-sitter-cli すると上書きで再設定が必要。"
fi

# ========================================
# 4. image.nvim 用 hererocks + magick rock
#    hererocks のビルドが過去に失敗していると bin/lua が無い壊れた状態が残るので掃除。
# ========================================
log "hererocks の状態を確認"
HEREROCKS_DIR="${NVIM_DATA}/lazy-rocks/hererocks"
if [[ -d "${HEREROCKS_DIR}" ]] && [[ ! -x "${HEREROCKS_DIR}/bin/lua" ]]; then
  log "  壊れた hererocks ディレクトリを削除"
  rm -rf "${HEREROCKS_DIR}"
fi

log "hererocks をビルド (Lua 5.1 + LuaRocks)"
nvim --headless "+Lazy! build hererocks" "+qa" 2>&1 | tail -5 || true

log "image.nvim をビルド (magick rock)"
nvim --headless "+Lazy! build image.nvim" "+qa" 2>&1 | tail -5 || true

# ========================================
# 5. lazygit (GitHub release から ~/.local/bin)
# ========================================
log "lazygit を確認"
if ! [[ -x "${LOCAL_BIN}/lazygit" ]]; then
  LAZYGIT_VERSION=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  log "  lazygit ${LAZYGIT_VERSION} を取得"
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" -o "${tmp}/lazygit.tar.gz"
  tar -xzf "${tmp}/lazygit.tar.gz" -C "${tmp}" lazygit
  install -m 0755 "${tmp}/lazygit" "${LOCAL_BIN}/lazygit"
  rm -rf "${tmp}"
else
  log "  lazygit は導入済み ($(${LOCAL_BIN}/lazygit --version | head -1))"
fi

# ========================================
# 6. delta (GitHub release から ~/.local/bin)
# ========================================
log "delta を確認"
if ! [[ -x "${LOCAL_BIN}/delta" ]]; then
  DELTA_VERSION=$(curl -fsSL "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
  log "  delta ${DELTA_VERSION} を取得"
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu.tar.gz" -o "${tmp}/delta.tar.gz"
  tar -xzf "${tmp}/delta.tar.gz" -C "${tmp}"
  install -m 0755 "${tmp}/delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu/delta" "${LOCAL_BIN}/delta"
  rm -rf "${tmp}"
else
  log "  delta は導入済み ($(${LOCAL_BIN}/delta --version))"
fi

# ========================================
# 7. PATH 確認
# ========================================
case ":${PATH}:" in
  *":${LOCAL_BIN}:"*) ;;
  *) warn "${LOCAL_BIN} が現在の PATH に無い。ログインシェル (~/.profile) では追加されるため、新規ターミナルで反映される。" ;;
esac

log "完了"

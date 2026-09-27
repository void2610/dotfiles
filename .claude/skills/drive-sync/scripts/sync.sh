#!/bin/bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/drive-sync"
PROJECTS_CONF="${CONFIG_DIR}/projects.conf"
DEST_ROOT="${HOME}/Documents/rclone"
REMOTE="${DRIVE_SYNC_REMOTE:-gdrive}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 他人所有の共有フォルダでは ListR (--fast-list 含む) がフォルダ単位で中身を取りこぼすため無効化する
LIST_FLAGS=(--disable ListR)

die() {
  echo "drive-sync: $*" >&2
  exit 1
}

usage() {
  echo "usage: $(basename "$0") <pull|status|ls|list> [repo]" >&2
  exit 2
}

resolve_repo() {
  if [ -n "${1:-}" ]; then
    echo "$1"
    return
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git リポジトリ外では repo 名を引数で指定してください"
  basename "$top"
}

lookup_folder_id() {
  local repo="$1"
  [ -f "$PROJECTS_CONF" ] || die "${PROJECTS_CONF} がありません"
  awk -v r="$repo" '$0 !~ /^[[:space:]]*#/ && $1 == r { print $2; exit }' "$PROJECTS_CONF"
}

run_rclone_sync() {
  local repo="$1"
  shift
  local folder_id dest repo_filter
  folder_id="$(lookup_folder_id "$repo")"
  [ -n "$folder_id" ] || die "${repo} は ${PROJECTS_CONF} に未登録です"
  command -v rclone >/dev/null || die "rclone が見つかりません"

  dest="${DEST_ROOT}/${repo}"
  case "$repo" in
    "" | */* | . | ..) die "不正な repo 名: ${repo}" ;;
  esac

  local args=(
    sync "${REMOTE},root_folder_id=${folder_id}:" "$dest"
    # 画像抽出の生成物は Drive に無いので、除外して sync の削除対象から外す
    --filter "- *.images/**"
    --filter-from "${CONFIG_DIR}/filters/_common.filter"
    --drive-export-formats md,csv,pdf
    # Drive 側の大量削除がローカルへ波及する事故の歯止め
    --max-delete 50
    "${LIST_FLAGS[@]}"
  )
  repo_filter="${CONFIG_DIR}/filters/${repo}.filter"
  [ -f "$repo_filter" ] && args+=(--filter-from "$repo_filter")

  mkdir -p "$dest"
  rclone "${args[@]}" "$@"
}

print_notes() {
  local notes="${CONFIG_DIR}/notes/${1}.md"
  [ -f "$notes" ] || return 0
  echo
  echo "--- フォルダの補足 (${notes}) ---"
  cat "$notes"
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift

case "$cmd" in
  pull)
    repo="$(resolve_repo "${1:-}")"
    run_rclone_sync "$repo" --stats-one-line -v
    python3 "${SCRIPT_DIR}/extract_images.py" "${DEST_ROOT}/${repo}"
    echo "drive-sync: ${DEST_ROOT}/${repo} を更新しました"
    print_notes "$repo"
    ;;
  status)
    repo="$(resolve_repo "${1:-}")"
    out="$(run_rclone_sync "$repo" --dry-run 2>&1)" || {
      echo "$out" >&2
      exit 1
    }
    diff_lines="$(grep 'Skipped' <<<"$out" || true)"
    echo "${diff_lines:-drive-sync: 差分なし}"
    print_notes "$repo"
    ;;
  ls)
    repo="$(resolve_repo "${1:-}")"
    folder_id="$(lookup_folder_id "$repo")"
    [ -n "$folder_id" ] || die "${repo} は ${PROJECTS_CONF} に未登録です"
    rclone lsf -R "${LIST_FLAGS[@]}" --drive-export-formats md,csv,pdf "${REMOTE},root_folder_id=${folder_id}:"
    ;;
  list)
    awk '$0 !~ /^[[:space:]]*#/ && NF >= 2 { print $1 }' "$PROJECTS_CONF"
    ;;
  *)
    usage
    ;;
esac

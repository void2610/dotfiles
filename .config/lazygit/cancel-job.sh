#!/usr/bin/env bash
# 実行中のコミットメッセージ生成ワーカーを中止する。llm-commit-msg.sh と同じ repo 単位ジョブ ID で pid を引き、プロセスグループごと停止して claude も巻き込む。
set -eu

notify() { terminal-notifier -title "lazygit" -message "$1" >/dev/null 2>&1 || true; }

jobs_dir="${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/jobs"
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
job_id="commit-$(printf '%s' "$top" | shasum | cut -c1-12)"
pid_file="$jobs_dir/${job_id}.pid"
done_file="$jobs_dir/${job_id}.done"

# showCommandLog:false 環境で読めるテキストを出す唯一の手段が「stderr + 非ゼロ終了によるエラーモーダル」のため、それで知らせる。
if [ ! -f "$pid_file" ]; then
  echo "中止対象の生成ジョブはありません。" >&2
  exit 1
fi

pid=$(cat "$pid_file" 2>/dev/null || echo "")
if [ -n "$pid" ]; then
  kill -TERM "-${pid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
fi

# run-detached.sh の前景待機を解放するため done マーカー (中止= 130) を書く。
echo 130 > "$done_file"
rm -f "$pid_file"
notify "コミットメッセージ生成を中止しました。"

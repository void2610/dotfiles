#!/usr/bin/env bash
# 引数のコマンドを新セッション(setsid 相当)で実行しつつ前景は完了を待つ。前景が待つことで lazygit の loadingText スピナーが出続け、lazygit を閉じて前景が殺されても worker は生き残って完走する (macOS に setsid が無いため perl で代替)。
set -eu

log="${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/detached.log"
jobs_dir="${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/jobs"
mkdir -p "$(dirname "$log")" "$jobs_dir"

# LG_JOB_ID があれば決定的なパスにして中止スクリプトから止められるようにする (無ければ一時ファイル)。
if [ -n "${LG_JOB_ID:-}" ]; then
  done_file="$jobs_dir/${LG_JOB_ID}.done"
  pid_file="$jobs_dir/${LG_JOB_ID}.pid"
else
  done_file=$(mktemp -u "${TMPDIR:-/tmp}/lg-detach.XXXXXX")
  pid_file=""
fi
rm -f "$done_file" "$pid_file"

# fork 後に setsid で worker を pty から切り離し perl 親は即戻る。worker は pid を記録し system() 実行後に rc を done_file へ残す。
LG_DETACH_LOG="$log" LG_DONE_FILE="$done_file" LG_PID_FILE="$pid_file" /usr/bin/perl -MPOSIX -e '
  my $pid = fork();
  die "fork failed: $!" unless defined $pid;
  exit 0 if $pid;
  POSIX::setsid();
  open(STDIN,  "<",  "/dev/null");
  open(STDOUT, ">>", $ENV{LG_DETACH_LOG});
  open(STDERR, ">>", $ENV{LG_DETACH_LOG});
  if ($ENV{LG_PID_FILE} ne "" and open(my $pf, ">", $ENV{LG_PID_FILE})) { print $pf $$; close($pf); }
  my $st = system(@ARGV);
  my $rc = $st == -1 ? 1 : ($st >> 8);
  if (open(my $fh, ">", $ENV{LG_DONE_FILE})) { print $fh $rc; close($fh); }
  unlink($ENV{LG_PID_FILE}) if $ENV{LG_PID_FILE} ne "";
  POSIX::_exit($rc);
' -- "$@"

# 完了マーカーが出るまで待機してスピナーを維持する。閉じられればこの待機ごと殺されるが worker は継続する。
waited=0
max_loops=1000 # 0.3s * 1000 = 約300秒で待機を諦める (worker 自体は継続)
while [ ! -e "$done_file" ]; do
  sleep 0.3
  waited=$((waited + 1))
  [ "$waited" -ge "$max_loops" ] && exit 0
done
rc=$(cat "$done_file" 2>/dev/null || echo 0)
# 130 は中止 (cancel-job.sh) を表す。失敗ではないため lazygit のエラーポップアップを出さないよう 0 にする。
[ "$rc" = "130" ] && rc=0
rm -f "$done_file" "$pid_file"
exit "$rc"

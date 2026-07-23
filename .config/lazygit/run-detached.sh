#!/usr/bin/env bash
# 引数のコマンドを新セッション(setsid 相当)で実行しつつ前景は完了を待つ。前景が待つことで lazygit の loadingText スピナーが出続け、lazygit を閉じて前景が殺されても worker は生き残って完走する (macOS に setsid が無いため perl で代替)。
set -eu

log="${XDG_CACHE_HOME:-$HOME/.cache}/lazygit/detached.log"
mkdir -p "$(dirname "$log")"
# worker が終了時に exit code を書き込む完了マーカー。存在＝完了。
done_file=$(mktemp -u "${TMPDIR:-/tmp}/lg-detach.XXXXXX")

# fork 後に setsid して worker を pty から切り離し、perl 親は即戻る。worker は system() でコマンドを実行し rc を done_file へ残す。
LG_DETACH_LOG="$log" LG_DONE_FILE="$done_file" /usr/bin/perl -MPOSIX -e '
  my $pid = fork();
  die "fork failed: $!" unless defined $pid;
  exit 0 if $pid;
  POSIX::setsid();
  open(STDIN,  "<",  "/dev/null");
  open(STDOUT, ">>", $ENV{LG_DETACH_LOG});
  open(STDERR, ">>", $ENV{LG_DETACH_LOG});
  my $st = system(@ARGV);
  my $rc = $st == -1 ? 1 : ($st >> 8);
  if (open(my $fh, ">", $ENV{LG_DONE_FILE})) { print $fh $rc; close($fh); }
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
rm -f "$done_file"
exit "$rc"

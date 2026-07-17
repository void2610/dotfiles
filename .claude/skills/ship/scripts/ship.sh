#!/usr/bin/env bash
set -euo pipefail

PHASES=(plan branch impl test format commit quiz pr review fix)
COPILOT_LOGIN="copilot-pull-request-reviewer"
FETCH_THREADS="$HOME/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh"

die() { echo "NG: $*" >&2; exit 1; }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "git リポジトリ内で実行すること"
branch=$(git rev-parse --abbrev-ref HEAD)
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || echo main)
# git-dir 配下に置くことで worktree ごとに独立し、git 管理にも乗らない
state_dir="$(git rev-parse --absolute-git-dir)/ship"
branch_file="$state_dir/${branch//\//__}.json"
default_file="$state_dir/${default_branch//\//__}.json"
# plan はブランチ作成前に起きるため、自ブランチの状態が無ければデフォルトブランチ起点の状態を引き継ぐ
state_file="$branch_file"
[[ ! -f "$branch_file" && -f "$default_file" ]] && state_file="$default_file"
config_file="$repo_root/.claude/ship.json"

state() { jq -r "$1" "$state_file" 2>/dev/null; }

require_state() { [[ -f "$state_file" ]] || die "状態ファイルがない。先に ship.sh init \"<goal>\" を実行すること"; }

update_state() {
  local tmp; tmp=$(mktemp)
  jq "$@" "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

config_cmd() { jq -r ".$1 // empty" "$config_file" 2>/dev/null || true; }

base_ref() {
  git rev-parse --verify -q "origin/$default_branch" >/dev/null 2>&1 && { echo "origin/$default_branch"; return; }
  git rev-parse --verify -q "$default_branch" >/dev/null 2>&1 && { echo "$default_branch"; return; }
  echo ""
}

# クイズゲートはこのホストのみ (dotfiles 共有先の他マシンには課さない)
quiz_enabled() { [[ "$(hostname -s)" == "PCmac24055" ]]; }

phase_mark() {
  local p="$1"
  [[ "$p" == quiz ]] && ! quiz_enabled && { echo skip; return; }
  [[ $(state ".done.$p // empty") != "" ]] && { echo done; return; }
  [[ $(state ".skipped.$p // empty") != "" ]] && { echo skip; return; }
  echo pending
}

next_phase() {
  local p
  for p in "${PHASES[@]}"; do
    [[ $(phase_mark "$p") == pending ]] && { echo "$p"; return; }
  done
  echo complete
}

unresolved_count() {
  [[ -x "$FETCH_THREADS" ]] || { echo "?"; return; }
  local out
  # 取得失敗と「未解決 0 件」を区別する (失敗を 0 扱いすると done fix が誤通過する)
  out=$("$FETCH_THREADS" 2>/dev/null) || { echo "?"; return; }
  [[ -z "$out" ]] && echo 0 || echo "$out" | grep -c .
}

verify_plan()   { [[ -n $(state '.goal // empty') ]] || die "goal が未記録。ship.sh init \"<goal>\" で計画を記録すること"; }
verify_branch() { [[ "$branch" != "$default_branch" ]] || die "まだ $default_branch にいる。branch-create スキルでブランチを切ること"; }

verify_impl() {
  ! git diff --quiet || ! git diff --cached --quiet && return 0
  [[ -n $(git ls-files --others --exclude-standard) ]] && return 0
  local base; base=$(base_ref)
  [[ -n "$base" && $(git rev-list --count "$base..HEAD") -gt 0 ]] && return 0
  die "変更が見当たらない (working tree clean かつ $default_branch から差分なし)"
}

run_config_cmd() {
  local key="$1" cmd
  cmd=$(config_cmd "$key")
  [[ -n "$cmd" ]] || die "$key コマンド未設定。$config_file に {\"$key\": \"<cmd>\"} を設定するか、ship.sh skip $key <理由> を使うこと"
  echo "実行: $cmd"
  (cd "$repo_root" && eval "$cmd") || die "$key コマンドが失敗 ($cmd)"
}

verify_test()   { run_config_cmd test; }
verify_format() { run_config_cmd format; }

verify_commit() {
  git diff --quiet && git diff --cached --quiet || die "未コミットの変更が残っている。commit スキルでコミットすること"
  local base; base=$(base_ref)
  if [[ -n "$base" ]]; then
    [[ $(git rev-list --count "$base..HEAD") -gt 0 ]] || die "コミットが 1 件も積まれていない"
  fi
  local untracked; untracked=$(git ls-files --others --exclude-standard | head -5)
  [[ -z "$untracked" ]] || echo "注意: untracked ファイルあり (意図的か確認):"$'\n'"$untracked"
}

verify_quiz() {
  local sha approved
  sha=$(git rev-parse HEAD)
  approved=$(state '.quiz.approved_sha // empty')
  [[ -n "$approved" ]] || die "クイズ未実施。push-quiz スキルで出題し、全問正答 + ユーザー許可後に ship.sh quiz approve を実行すること"
  [[ "$approved" == "$sha" ]] || die "クイズ承認 ($approved) が現 HEAD ($sha) と不一致。実装が変わったので push-quiz スキルで再出題すること"
}

verify_pr() {
  # quiz 完了後に積み直した場合、古い承認のまま push させない
  if quiz_enabled; then [[ -n $(state '.skipped.quiz // empty') ]] || verify_quiz; fi
  local st; st=$(gh pr view --json state --jq .state 2>/dev/null || true)
  [[ "$st" == "OPEN" ]] || die "現在ブランチに OPEN な PR がない。pr-create スキルで作成すること"
}

# gh pr checks は fail 時 exit 1 / pending 時 exit 8 を返すため、JSON 出力で判定する
ci_summary() {
  local out
  out=$(gh pr checks --json bucket --jq '[.[].bucket] | join(",")' 2>/dev/null) || true
  [[ -z "$out" ]] && { echo none; return; }
  [[ "$out" == *pending* ]] && { echo pending; return; }
  [[ "$out" == *fail* || "$out" == *cancel* ]] && { echo fail; return; }
  echo pass
}

verify_review() {
  local n
  n=$(gh pr view --json reviews --jq "[.reviews[] | select(.author.login == \"$COPILOT_LOGIN\")] | length" 2>/dev/null || echo 0)
  [[ "$n" -gt 0 ]] || die "Copilot レビューが未到着 (poll-copilot-review.sh の完了を待つこと)"
  local ci; ci=$(ci_summary)
  case "$ci" in
    pending) die "CI チェックが実行中。完了を待つこと (gh pr checks)" ;;
    fail)    die "CI チェックが失敗している。原因を修正して push すること (gh pr checks)" ;;
  esac
}

verify_fix() {
  local n; n=$(unresolved_count)
  [[ "$n" == "?" ]] && die "未解決スレッド数を取得できない (fetch_unresolved_threads.sh を確認)"
  [[ "$n" -eq 0 ]] || die "未解決レビュースレッドが $n 件残っている。pr-review-fix スキルで対応すること"
}

cmd=${1:-status}
shift || true

case "$cmd" in
  init)
    [[ $# -ge 1 ]] || die "Usage: ship.sh init \"<goal>\""
    mkdir -p "$state_dir"
    jq -n --arg goal "$*" --arg branch "$branch" --arg ts "$(date -u +%FT%TZ)" \
      '{goal: $goal, branch: $branch, created: $ts, done: {}, skipped: {}, checkpoints: []}' > "$state_file"
    update_state ".done.plan = \"$(date -u +%FT%TZ)\""
    echo "初期化完了: $state_file (plan 記録済み)"
    ;;
  status)
    if [[ ! -f "$state_file" ]]; then
      echo "state=none branch=$branch default_branch=$default_branch"
      echo "状態ファイルなし。新規フローは ship.sh init \"<goal>\" から"
      exit 0
    fi
    echo "branch=$branch goal=$(state .goal)"
    local_next=$(next_phase)
    for p in "${PHASES[@]}"; do
      mark=$(phase_mark "$p")
      cur=""; [[ "$p" == "$local_next" ]] && cur=" <- next"
      cp=""; state '.checkpoints[]' | grep -qx "$p" && cp=" [checkpoint]"
      echo "  $p: $mark$cp$cur"
    done
    echo "worktree_dirty=$(git status --porcelain | grep -q . && echo yes || echo no)"
    pr_url=$(gh pr view --json url --jq .url 2>/dev/null || echo none)
    echo "pr=$pr_url"
    if [[ "$pr_url" != none ]]; then echo "ci=$(ci_summary)"; fi
    ;;
  next)
    require_state
    n=$(next_phase)
    cp=no
    [[ "$n" != complete ]] && state '.checkpoints[]' | grep -qx "$n" && cp=yes
    echo "next=$n checkpoint=$cp"
    ;;
  done)
    require_state
    p=${1:-}; [[ " ${PHASES[*]} " == *" $p "* ]] || die "不明なフェーズ: '$p' (${PHASES[*]})"
    n=$(next_phase)
    [[ "$p" == "$n" || $(phase_mark "$p") == done ]] || die "順序違反: next=${n}。先に ${n} を完了させるか ship.sh skip ${n} <理由> を使うこと"
    "verify_$p"
    update_state ".done.\"$p\" = \"$(date -u +%FT%TZ)\""
    if [[ "$p" == branch && "$state_file" != "$branch_file" ]]; then
      update_state ".branch = \"$branch\""
      mv "$state_file" "$branch_file"
      state_file="$branch_file"
    fi
    echo "OK: $p 完了。next=$(next_phase)"
    ;;
  skip)
    require_state
    p=${1:-}; shift || true
    [[ " ${PHASES[*]} " == *" $p "* ]] || die "不明なフェーズ: '$p'"
    [[ $# -ge 1 ]] || die "skip には理由が必須: ship.sh skip $p <理由>"
    update_state ".skipped.\"$p\" = \"$*\""
    echo "OK: $p をスキップ (理由: $*)。next=$(next_phase)"
    ;;
  quiz)
    require_state
    sub=${1:-status}
    case "$sub" in
      # ユーザーが全問正答し push を明示許可した後にのみ実行してよい (push-quiz スキル参照)
      approve) update_state ".quiz = {approved_sha: \"$(git rev-parse HEAD)\", approved_at: \"$(date -u +%FT%TZ)\"}"; echo "OK: quiz 承認を HEAD ($(git rev-parse --short HEAD)) に記録" ;;
      revoke)  update_state "del(.quiz)"; echo "OK: quiz 承認を取り消した" ;;
      status)  state '.quiz // "未承認"' ;;
      *) die "Usage: ship.sh quiz approve|revoke|status" ;;
    esac
    ;;
  checkpoint)
    require_state
    sub=${1:-list}; p=${2:-}
    case "$sub" in
      add)    update_state ".checkpoints = (.checkpoints + [\"$p\"] | unique)"; echo "OK: $p の前で停止する" ;;
      remove) update_state ".checkpoints -= [\"$p\"]"; echo "OK: $p のチェックポイントを解除" ;;
      list)   state '.checkpoints[]' ;;
      *) die "Usage: ship.sh checkpoint add|remove|list [phase]" ;;
    esac
    ;;
  *)
    die "Usage: ship.sh init|status|next|done|skip|checkpoint|quiz"
    ;;
esac

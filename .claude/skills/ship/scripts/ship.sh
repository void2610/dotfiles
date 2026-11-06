#!/usr/bin/env bash
set -euo pipefail

PHASES=(plan branch impl test format knowledge commit explain report pr review fix)
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
# stacked PR (gh stack) のメタデータ。worktree からでも共通の git-dir を指す
stack_file="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo /nonexistent)/gh-stack"

state() { jq -r "$1" "$state_file" 2>/dev/null; }

# status 表示用。"develop の 2/3 段目" 形式。stack 外なら空
stack_position() {
  [[ -f "$stack_file" ]] || return 0
  jq -r --arg b "$branch" '
    .stacks[]? | select([.branches[]?.branch] | index($b)) |
    [.branches[]?.branch] as $bs |
    "\(.trunk.branch) の \(($bs | index($b)) + 1)/\($bs | length) 段目"
  ' "$stack_file" 2>/dev/null || true
}

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

# 解説・報告フェーズはこのホストのみ (dotfiles 共有先の他マシンには課さない)
personal_host() { [[ "$(hostname -s)" == "PCmac24055" ]]; }

phase_mark() {
  local p="$1"
  [[ "$p" == explain || "$p" == report ]] && ! personal_host && { echo skip; return; }
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

# Knowledge/ (OKF) への永続化を「検討した」記録を強制する。書かない判断も理由付きで記録する
verify_knowledge() {
  [[ -n $(state '.knowledge.note // empty') ]] || die "Knowledge 永続化が未検討。得た知見を Knowledge/ に書くか、書かない理由を ship.sh knowledge \"<書いたファイル or 不要の理由>\" で記録すること"
}

verify_commit() {
  # ship.json の ignoreDirty (パス配列) は clean 判定から除外する (フローと無関係なユーザー変更でブロックしないため)
  local -a ex=()
  local ignored
  while IFS= read -r ignored; do [[ -n "$ignored" ]] && ex+=(":(exclude)$ignored"); done \
    < <(jq -r '(.ignoreDirty // [])[]' "$config_file" 2>/dev/null || true)
  # サブディレクトリから呼ばれても全体を見るため、pathspec ごとリポジトリルート基準に固定する
  git -C "$repo_root" diff --quiet -- . ${ex[@]+"${ex[@]}"} \
    && git -C "$repo_root" diff --cached --quiet -- . ${ex[@]+"${ex[@]}"} \
    || die "未コミットの変更が残っている。commit スキルでコミットすること (無関係な変更は ship.json の ignoreDirty に登録可)"
  local base; base=$(base_ref)
  if [[ -n "$base" ]]; then
    [[ $(git -C "$repo_root" rev-list --count "$base..HEAD") -gt 0 ]] || die "コミットが 1 件も積まれていない"
  fi
  local untracked; untracked=$(git -C "$repo_root" ls-files --others --exclude-standard | head -5)
  [[ -z "$untracked" ]] || echo "注意: untracked ファイルあり (意図的か確認):"$'\n'"$untracked"
}

# 実装報告のユーザー承認は HEAD SHA に紐づけ、その後コミットが積まれたら失効させる
verify_report() {
  local sha approved
  sha=$(git rev-parse HEAD)
  approved=$(state '.report.approved_sha // empty')
  [[ -n "$approved" ]] || die "実装報告が未承認。実装報告を提示し、ユーザー承認後に ship.sh report approve を実行すること"
  [[ "$approved" == "$sha" ]] || die "報告承認 ($approved) が現 HEAD ($sha) と不一致。実装が変わったので再報告して承認を取り直すこと"
}

# 解説ページも HEAD SHA に紐づけ、生成後に積んだコミットが解説から漏れたまま push させない
verify_explain() {
  local sha path
  sha=$(git rev-parse HEAD)
  path=$(state '.explain.path // empty')
  [[ -n "$path" ]] || die "解説ページが未生成。explain-diff-html スキルで $default_branch からの差分の解説ページを作り、ship.sh explain open <html パス> を実行すること"
  [[ -f "$path" ]] || die "解説ページ ($path) が見当たらない。explain-diff-html スキルで再生成すること"
  [[ $(state '.explain.sha // empty') == "$sha" ]] || die "解説ページ ($path) の対象が現 HEAD ($sha) と不一致。実装が変わったので explain-diff-html スキルで再生成すること"
}

verify_pr() {
  # explain/report 完了後に積み直した場合、古い承認・解説のまま push させない
  if personal_host; then
    [[ -n $(state '.skipped.report // empty') ]] || verify_report
    [[ -n $(state '.skipped.explain // empty') ]] || verify_explain
  fi
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
  [[ "$n" -gt 0 ]] || die "Copilot レビューが未到着 (pr-watch Mod の通知を待つか gh pr view --json reviews で確認すること)"
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
    pos=$(stack_position)
    [[ -n "$pos" ]] && echo "stack=$pos (段の追加は gh stack add、段間の移動は gh stack up/down/switch)"
    echo "worktree_dirty=$(git status --porcelain | grep -q . && echo yes || echo no)"
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
  report)
    require_state
    sub=${1:-status}
    case "$sub" in
      # ユーザーが実装報告を読み承認した後にのみ実行してよい
      approve) update_state ".report = {approved_sha: \"$(git rev-parse HEAD)\", approved_at: \"$(date -u +%FT%TZ)\"}"; echo "OK: report 承認を HEAD ($(git rev-parse --short HEAD)) に記録" ;;
      revoke)  update_state "del(.report)"; echo "OK: report 承認を取り消した" ;;
      status)  state '.report // "未承認"' ;;
      *) die "Usage: ship.sh report approve|revoke|status" ;;
    esac
    ;;
  explain)
    require_state
    sub=${1:-status}
    case "$sub" in
      open)
        f=${2:-}
        [[ -f "$f" ]] || die "Usage: ship.sh explain open <explain-diff-html で生成した HTML のパス>"
        # verify は別の cwd から呼ばれうるため絶対パスで記録する
        f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
        open "$f"
        update_state --arg path "$f" --arg sha "$(git rev-parse HEAD)" --arg ts "$(date -u +%FT%TZ)" \
          '.explain = {path: $path, sha: $sha, opened_at: $ts}'
        echo "OK: 解説ページをブラウザで開き、HEAD ($(git rev-parse --short HEAD)) に紐づけて記録: $f"
        ;;
      status) state '.explain // "未生成"' ;;
      *) die "Usage: ship.sh explain open <html パス>|status" ;;
    esac
    ;;
  knowledge)
    require_state
    [[ $# -ge 1 ]] || die "Usage: ship.sh knowledge \"<書いたファイル or 不要の理由>\""
    update_state ".knowledge = {note: \"$*\", at: \"$(date -u +%FT%TZ)\"}"
    echo "OK: knowledge 検討を記録: $*"
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
  abort)
    require_state
    goal=$(state .goal)
    rm -f "$state_file"
    echo "解除完了: ship フロー (goal=$goal) の状態を削除した"
    ;;
  *)
    die "Usage: ship.sh init|status|next|done|skip|checkpoint|knowledge|report|explain|abort"
    ;;
esac

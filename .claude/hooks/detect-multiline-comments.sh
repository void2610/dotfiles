#!/bin/bash
# CLAUDE.md「Max 1 line per comment」違反 (連続フルラインコメント) を検知し修正を促す PostToolUse hook
set -u

input=$(cat)
new=$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"$input")
[ -z "$new" ] && exit 0
old=$(jq -r '.tool_input.old_string // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // ""' <<<"$input")

case "$path" in
  *.sh|*.bash|*.zsh|*.py|*.rb|*.pl|*.nix|*.toml|*.yml|*.yaml|*.conf|*.tf|*.fish|*.mk|Makefile) m='#' ;;
  *.c|*.h|*.cpp|*.hpp|*.cc|*.cs|*.m|*.mm|*.swift|*.js|*.jsx|*.ts|*.tsx|*.go|*.rs|*.java|*.kt|*.kts|*.scala|*.dart|*.zig) m='//' ;;
  *.lua|*.hs|*.sql|*.elm) m='--' ;;
  *.vim|*vimrc) m='"' ;;
  *.el|*.lisp|*.clj) m=';' ;;
  *) exit 0 ;;
esac

# doc コメント (C#/Rust の ///) はブロック検知から除外
dm=''
[ "$m" = '//' ] && dm='///'

# Write (old_string なし) は git HEAD の内容を既存扱いにする
if [ -z "$old" ] && [ -f "$path" ]; then
  dir=$(dirname "$path")
  rel=$(git -C "$dir" ls-files --full-name -- "$path" 2>/dev/null | head -1)
  [ -n "$rel" ] && old=$(git -C "$dir" show "HEAD:$rel" 2>/dev/null || true)
fi

# 2行以上連続するフルラインコメントブロックを \x1e 区切りで抽出 (shebang は除外)
extract_blocks() {
  awk -v m="$m" -v dm="$dm" '
    function flush() { if (n >= 2) printf "%s\x1e", buf; buf = ""; n = 0 }
    {
      l = $0; sub(/^[ \t]+/, "", l)
      if (index(l, m) == 1 && l !~ /^#!/ && (dm == "" || index(l, dm) != 1)) { buf = buf (n ? "\n" : "") $0; n++ } else flush()
    }
    END { flush() }
  '
}

blocks=$(extract_blocks <<<"$new")
[ -z "$blocks" ] && exit 0

found=""
while IFS= read -r -d $'\x1e' b; do
  case "$old" in *"$b"*) continue ;; esac
  found="${found}${b}"$'\n----\n'
done <<<"$blocks"
[ -z "$found" ] && exit 0

cat >&2 <<EOF
CLAUDE.md の Comments ルール違反の可能性: ${path} に複数行コメントブロックが追加された。
第一の対処は「削除」である。1 行への圧縮で形式だけ合わせるな。各行について「非自明な WHY を述べているか」を判定し、WHAT の説明・Usage・列挙は削除、残せるのは WHY の 1 行のみ:
- Comments only for non-obvious WHY (workarounds, constraints, domain knowledge). Never restate WHAT the code does.
- Max 1 line per comment. No multi-line comment blocks unless asked, or a complex constraint / domain knowledge genuinely cannot be summarized in one line.
- Never write comments describing the change process (e.g. "fixed", "changed to", "added").
- Preserve existing comments unless they become factually wrong.
- Write comments in Japanese.
検出ブロック:
${found}
EOF
exit 2

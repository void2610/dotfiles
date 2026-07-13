#!/bin/bash
# CLAUDE.md「Max 1 line per comment」違反 (連続フルラインコメント) を検知し修正を促す PostToolUse hook
set -u

input=$(cat)
new=$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"$input")
[ -z "$new" ] && exit 0
old=$(jq -r '.tool_input.old_string // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // ""' <<<"$input")

case "$path" in
*.sh | *.bash | *.zsh | *.py | *.rb | *.pl | *.nix | *.toml | *.yml | *.yaml | *.conf | *.tf | *.fish | *.mk | Makefile) m='#' ;;
*.c | *.h | *.cpp | *.hpp | *.cc | *.cs | *.m | *.mm | *.swift | *.js | *.jsx | *.ts | *.tsx | *.go | *.rs | *.java | *.kt | *.kts | *.scala | *.dart | *.zig) m='//' ;;
*.lua | *.hs | *.sql | *.elm) m='--' ;;
*.vim | *vimrc) m='"' ;;
*.el | *.lisp | *.clj) m=';' ;;
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

# 2行以上連続するフルラインコメントブロックを \x1e 区切りで抽出 (shebang・@ディレクティブ行は除外)
extract_blocks() {
  awk -v m="$m" -v dm="$dm" '
    function flush() { if (n >= 2) printf "%s\x1e", buf; buf = ""; n = 0 }
    {
      l = $0; sub(/^[ \t]+/, "", l)
      if (index(l, m) == 1 && l !~ /^#!/ && (dm == "" || index(l, dm) != 1)) {
        r = substr(l, length(m) + 1)
        sub(/^[-!\/*#";]*[ \t]*/, "", r)
        if (r ~ /^@/) next
        buf = buf (n ? "\n" : "") $0; n++
      } else flush()
    }
    END { flush() }
  '
}

blocks=$(extract_blocks <<<"$new")
[ -z "$blocks" ] && exit 0

# @行を挟む既存ブロックは抽出結果が非連続になり raw 比較で一致しないため、old 側の抽出結果とも比較する
old_blocks=$(extract_blocks <<<"$old")

found=""
while IFS= read -r -d $'\x1e' b; do
  case "$old" in *"$b"*) continue ;; esac
  case "$old_blocks" in *"$b"*) continue ;; esac
  found="${found}${b}"$'\n----\n'
done <<<"$blocks"
[ -z "$found" ] && exit 0

cat >&2 <<EOF
CLAUDE.md の Comments ルール違反の可能性: ${path} に複数行コメントブロックが追加された。
以下のワークフローを今回の Edit 1 回で完結させる (段階的な削減はしない):

1. コメントが WHY (非自明な理由: workaround・制約・ドメイン知識) / Why not (採らなかった選択肢とその理由) を述べているか確認する
2. 述べていない → 削除する
   - what コメント (次の行が何をするかの言い換え) — What の説明はテストコードの責務
   - Usage・列挙
   - 変更過程の説明 (fixed / changed 等)
3. 述べている → 1 行に削減する
   - 要約不能な複雑な制約/ドメイン知識のみ、そのまま残して再編集しない

事実として正しい既存コメントは保持する。

## 検出ブロック
${found}
EOF
exit 2

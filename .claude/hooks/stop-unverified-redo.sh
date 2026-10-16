#!/bin/bash
# 最後の応答に未確認を表す言い回しがあれば停止を止め、確かめてから答え直させる
input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
session_id=$(echo "$input" | jq -r '.session_id // "none"')
[ -f "$transcript" ] || exit 0

# 直近のユーザー入力より後の assistant のテキストだけを見る
text=$(jq -rs '
  (map(.type == "user" and ((.message.content | type) == "string" or any(.message.content[]?; .type == "text"))) | rindex(true)) as $u
  | .[(($u // -1) + 1):]
  | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
  | join("\n")
' "$transcript" 2>/dev/null)

# 動詞 (確かめる・確認・検証・調べる・裏取り・読む・見る) の未実施と「未確認・未検証・未読」を拾う
pattern='(確かめ|調べ|見|聞い|試し)て(い)?(ない|ません|なかった)|読んで(い)?(ない|ません|なかった)|(確かめ|調べ)られ(てい)?(ない|ません|なかった)|(確認|検証|照合|突き合わせ|裏取り|実測|動作確認)(は|を|が)?(して|できて|でき|されて)(い)?(ない|ません|なかった)|未確認|未検証|未読|未調査|未照合|裏取りなし|確認なし|要確認|確認待ち'
hit=$(echo "$text" | grep -oE "$pattern" | sort -u | head -5 | paste -sd '、' -)

counter="${TMPDIR:-/tmp}/claude-unverified-redo-${session_id}"
if [ -z "$hit" ]; then
  rm -f "$counter"
  exit 0
fi

# 確かめようがない事項で無限に止め続けないよう、連続 3 回で打ち切る
count=$(cat "$counter" 2>/dev/null || echo 0)
if [ "$count" -ge 3 ]; then
  rm -f "$counter"
  exit 0
fi
echo $((count + 1)) > "$counter"

jq -n --arg hit "$hit" '{
  decision: "block",
  reason: ("応答に未確認を表す言い回し (" + $hit + ") が含まれている。確かめていない事項を実際に調べて (コード・GitHub・Notion・Slack 等の一次情報を取り直して) 事実を確定させ、その結果で応答をやり直すこと。どうしても確かめられない場合は、何を試してなぜ確かめられないのかを具体的に書くこと。")
}'

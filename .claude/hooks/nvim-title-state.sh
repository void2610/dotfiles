#!/bin/bash
# nvim の :terminal 内で動く Claude の状態を親 nvim のタブタイトルへ通知する
state="$1"
input=$(cat)
[ -z "$NVIM" ] && exit 0

# Notification は種別で入力待ちか単なるアイドル通知かを分ける
if [ "$state" = "notification" ]; then
  case "$(echo "$input" | jq -r '.notification_type // empty')" in
    idle_prompt) state="idle" ;;
    *) state="waiting" ;;
  esac
fi

# hook の完了を nvim の応答待ちで遅らせないよう切り離す
nvim --server "$NVIM" --remote-expr "luaeval('ClaudeTitleState(_A)', '$state')" >/dev/null 2>&1 &
exit 0

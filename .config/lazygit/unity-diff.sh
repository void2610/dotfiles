#!/bin/sh
# GIT_EXTERNAL_DIFF 形式 (path old-file old-hex old-mode new-file new-hex new-mode ...) で呼ばれ、Unity YAML のみ prefablens に振り分ける
path=$1
old=$2
new=$5

# 配色は snacks picker の fancy diff (tokyonight-moon、.config/bat/themes/tokyonight_moon.tmTheme 要 `bat cache --build`) に合わせる
run_delta() {
  diff -u --label "a/$path" --label "b/$path" "$old" "$new" | delta \
    --paging=never --line-numbers \
    --syntax-theme=tokyonight_moon \
    --minus-style='syntax #4b2a3d' --minus-non-emph-style='syntax #4b2a3d' \
    --minus-emph-style='syntax #6b2e43' --minus-empty-line-marker-style='syntax #4b2a3d' \
    --plus-style='syntax #2a4556' --plus-non-emph-style='syntax #2a4556' \
    --plus-emph-style='syntax #305f6f' --plus-empty-line-marker-style='syntax #2a4556' \
    --line-numbers-minus-style='#e26a75' --line-numbers-plus-style='#b8db87' \
    --line-numbers-zero-style='#3b4261' \
    --line-numbers-left-format='{nm:>4} ' --line-numbers-right-format='{np:>4}  ' \
    --hunk-header-style='line-number syntax' --hunk-header-decoration-style='#3b4261 box' \
    --hunk-header-line-number-style='#82aaff' \
    --file-style='#82aaff bold' --file-decoration-style='#3b4261 ul'
}

# delta 風に add/remove の行背景を敷く。ツリー書式ではなく行内の前景色 (緑=追加値, 赤=削除値) で判定し、変更行 (赤緑混在 or 黄マーカー) は背景なし
colorize() {
  awk '
    BEGIN {
      add = "\033[48;2;42;69;86m"    # delta --plus-style と同じ #2a4556
      del = "\033[48;2;75;42;61m"    # delta --minus-style と同じ #4b2a3d
      chg = "\033[48;2;74;60;37m"    # 変更行はマーカーの黄に合わせた暗アンバー #4a3c25
    }
    {
      g = index($0, "\033[32m"); r = index($0, "\033[31m"); y = index($0, "\033[33m")
      bg = ""
      if (y || (r && g)) bg = chg
      else if (g)        bg = add
      else if (r)        bg = del
      if (bg == "") { print; next }
      line = $0
      gsub(/\033\[0m/, "\033[0m" bg, line)   # リセットで背景が消えるため直後に敷き直す
      printf "%s%s\033[K\033[0m\n", bg, line
    }
  '
}

# prefablens の対応拡張子 (cli/src/unity_path.zig の 26 種) を大文字小文字無視で照合する
case "$(printf %s "$path" | tr '[:upper:]' '[:lower:]')" in
  *.prefab | *.unity | *.asset | *.mat | *.anim | *.controller | \
  *.overridecontroller | *.physicmaterial | *.physicsmaterial2d | \
  *.playable | *.mask | *.brush | *.flare | *.fontsettings | *.guiskin | \
  *.giparams | *.rendertexture | *.spriteatlas | *.spriteatlasv2 | \
  *.terrainlayer | *.mixer | *.shadervariants | *.preset | *.signal | \
  *.lighting | *.scenetemplate)
    # 追加/削除は片側が /dev/null になり prefablens がパスと解釈できないため delta へ回す
    if [ "$old" = /dev/null ] || [ "$new" = /dev/null ]; then
      run_delta
    else
      # 2ファイル比較モードはリポジトリルートを自動検出しないため、guid 解決用に $path の祖先から Unity プロジェクトルートを探す
      proj=$(dirname "$path")
      while [ "$proj" != "." ] && [ "$proj" != "/" ]; do
        [ -d "$proj/ProjectSettings" ] && [ -d "$proj/Assets" ] && break
        proj=$(dirname "$proj")
      done
      if [ -d "$proj/ProjectSettings" ] && [ -d "$proj/Assets" ]; then
        prefablens --color --project "$proj" "$old" "$new" | colorize
      else
        prefablens --color "$old" "$new" | colorize
      fi
    fi
    ;;
  *)
    run_delta
    ;;
esac

# diff(1) は差分ありで 1 を返すが、外部 diff は非 0 終了を git がエラー扱いするため常に 0 で終える
exit 0

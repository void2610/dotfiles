#!/bin/sh
# lazygit (gocui) はエスケープを素通ししないため、画像転送だけ /dev/tty へ直書きし本文は Unicode placeholder で描く。
path=$1
old=$2
new=$3

# 表示幅 (セル数)。lazygit のメインビュー幅は取得できないため固定値 (環境変数で調整可)。
max_cols=${LG_IMG_COLS:-36}
max_rows=${LG_IMG_ROWS:-24}

# kitty gen/rowcolumn-diacritics.txt の先頭 64 個 (行/列番号のエンコードに使う)。
DIACRITICS="0305 030D 030E 0310 0312 033D 033E 033F 0346 034A 034B 034C 0350 0351 0352 0357 035B 0363 0364 0365 0366 0367 0368 0369 036A 036B 036C 036D 036E 036F 0483 0484 0485 0486 0487 0592 0593 0594 0595 0597 0598 0599 059C 059D 059E 059F 05A0 05A1 05A8 05A9 05AB 05AC 05AF 05C4 0610 0611 0612 0613 0614 0615 0616 0617 0657 0658"

# 画像サイズを "W H" で返す。取得失敗は空文字。
img_size() {
  sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null |
    awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if(w&&h) print w, h}'
}

# アスペクト比 (セルの縦横比 ≒ 2:1 を考慮) から表示セル数を "cols rows" で返す
cell_geometry() {
  awk -v w="$1" -v h="$2" -v mc="$max_cols" -v mr="$max_rows" 'BEGIN {
    c = mc; r = int(c * h / w / 2 + 0.5)
    if (r < 1) r = 1
    if (r > mr) { r = mr; c = int(r * w / h * 2 + 0.5); if (c < 1) c = 1 }
    print c, r
  }'
}

# lazygit の diff 用 PTY や nvim 内蔵端末 (APC バッファ上限あり) を挟まないよう、祖先最上位の実 PTY へ直接書く
real_tty() {
  pid=$PPID
  found=""
  while [ "$pid" -gt 1 ] 2>/dev/null; do
    t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$t" ] && [ "$t" != "??" ] && found=$t
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] || break
  done
  if [ -n "$found" ]; then echo "/dev/$found"; else echo /dev/tty; fi
}

# 画像を PNG 化して仮想配置 (a=T,U=1) で実端末に転送する。placeholder 出力は行わない
transmit() { # $1=画像 $2=image id $3=cols $4=rows
  out=$(real_tty)
  # -w 判定は tty 非接続でも真になりうるため、実際に開けるかで判定する
  { : >"$out"; } 2>/dev/null || return 1
  png=$(mktemp -t lg-img).png
  sips -s format png "$1" --out "$png" >/dev/null 2>&1 || { rm -f "$png"; return 1; }
  # ペイロードは 4096 バイトごとに分割し、m=1 で継続・空の m=0 で終端する
  base64 <"$png" | tr -d '\n' | fold -w 4096 |
    awk -v id="$2" -v c="$3" -v r="$4" '
      NR == 1 { printf "\033_Ga=T,q=2,U=1,f=100,t=d,i=%d,c=%d,r=%d,m=1;%s\033\\", id, c, r, $0; next }
      { printf "\033_Gm=1;%s\033\\", $0 }
      END { printf "\033_Gm=0\033\\" }
    ' >"$out"
  st=$?
  rm -f "$png"
  return $st
}

# placeholder のセル群を標準出力へ出す。fg の 256 色インデックスが image id を指す
placeholders() { # $1=image id $2=cols $3=rows
  awk -v id="$1" -v c="$2" -v r="$3" -v dtab="$DIACRITICS" '
    function h2d(h,  i, n, ch) {
      n = 0
      for (i = 1; i <= length(h); i++) {
        ch = substr(h, i, 1)
        n = n * 16 + index("0123456789ABCDEF", toupper(ch)) - 1
      }
      return n
    }
    # 対象 diacritics は全て U+0800 未満なので 2 バイト UTF-8 で足りる
    function utf8_2(cp) { return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64) }
    BEGIN {
      split(dtab, hx, " ")
      ph = "\364\216\273\256"   # U+10EEEE
      for (row = 1; row <= r; row++) {
        line = ""
        for (col = 1; col <= c; col++)
          line = line ph utf8_2(h2d(hx[row])) utf8_2(h2d(hx[col]))
        printf "\033[38;5;%dm%s\033[39m\n", id, line
      }
    }'
}

# 1 枚描画 (ラベル行 + 転送 + placeholder)。失敗時はサイズ情報だけ出す
render() { # $1=画像 $2=image id $3=ラベル色 $4=ラベル
  size=$(img_size "$1")
  if [ -z "$size" ]; then
    printf '\033[%sm%s\033[0m %s (%s bytes, preview unavailable)\n' "$3" "$4" "$path" "$(wc -c <"$1" | tr -d ' ')"
    return
  fi
  w=${size% *}; h=${size#* }
  geo=$(cell_geometry "$w" "$h")
  cols=${geo% *}; rows=${geo#* }
  printf '\033[%sm%s\033[0m %s (%dx%d, %s bytes)\n' "$3" "$4" "$path" "$w" "$h" "$(wc -c <"$1" | tr -d ' ')"
  if transmit "$1" "$2" "$cols" "$rows"; then
    placeholders "$2" "$cols" "$rows"
  else
    echo "(image transfer failed)"
  fi
}

# image id は path から導出し、複数画像が同一ビューに並んでも衝突しにくくする (old=偶数 / new=奇数)
base=$(printf %s "$path" | cksum | awk '{print $1 % 127 + 1}')

if [ "$old" != /dev/null ]; then
  render "$old" $((base * 2)) "31" "−"
fi
if [ "$old" != /dev/null ] && [ "$new" != /dev/null ]; then
  echo
fi
if [ "$new" != /dev/null ]; then
  render "$new" $((base * 2 + 1)) "32" "+"
fi

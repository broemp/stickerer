#!/usr/bin/env bash
# make-demo-stickers.sh - builds offline sample stickers for the screenshots from spinning-cat.gif.
# Output: <outdir>/NN.png (first frame thumbnail) and NN.webp (512x512, what the app would store).
# Usage: ./make-demo-stickers.sh [outdir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GIF="$(dirname "$HERE")/Stickerer/spinning-cat.gif"
OUT="${1:-$HERE/.build/demo-stickers}"
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.webp

# frame | hue (100 = unchanged) | rotate | flop(1/0) | saturation | caption (front-facing frames only)
VARIANTS=(
  "0   100 0   0 100 |"
  "20  60  -8  1 130 | LOL"
  "83  140 6   0 120 |"
  "10  180 -4  1 110 | mood"
  "72  80  10  0 140 | no."
  "92  120 -10 1 100 |"
  "5   45  4   0 125 | wow"
  "0   160 -6  1 135 |"
  "20  90  8   0 115 | ok"
  "83  70  -3  1 120 | yes"
  "10  110 12  0 130 |"
  "72  150 -12 1 105 | meh"
)
i=0
for v in "${VARIANTS[@]}"; do
  i=$((i + 1)); n=$(printf '%02d' "$i")
  spec="${v%%|*}"; caption="$(echo "${v#*|}" | xargs)"
  read -r frame hue rot flop sat <<<"$spec"
  flip=(); [ "$flop" = 1 ] && flip=(-flop)
  magick "$GIF[$frame]" -coalesce -background none -trim +repage "${flip[@]}" \
    -modulate 100,"$sat","$hue" -background none -rotate "$rot" -trim +repage \
    -resize 440x440 -gravity center -background none -extent 512x512 PNG32:"$OUT/$n.full.png"
  if [ -n "$caption" ]; then
    magick "$OUT/$n.full.png" -font /System/Library/Fonts/SFNSRounded.ttf -pointsize 110 -gravity south \
      -stroke black -strokewidth 14 -fill black -annotate +0+6 "$caption" \
      -stroke none -fill white -annotate +0+6 "$caption" PNG32:"$OUT/$n.full.png"
  fi
  magick "$OUT/$n.full.png" -quality 70 "$OUT/$n.webp"
  magick "$OUT/$n.full.png" -resize 256x256 "$OUT/$n.png"
  rm "$OUT/$n.full.png"
done
echo "ok  ${#VARIANTS[@]} demo stickers in $OUT"

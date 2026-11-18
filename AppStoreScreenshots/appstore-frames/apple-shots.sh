#!/usr/bin/env bash
# apple-shots.sh - resize images to App Store Connect screenshot sizes (iPhone 6.1" / 6.3" / 6.9", iPad 13")
#
# Usage: ./apple-shots.sh [-s 6.1|6.3|6.9|13] [-m pad|crop|stretch] [-b color] [-o outdir] [input_dir]
#
#   -s  display size (default 6.9)
#         6.1" -> 1179x2556 (portrait) / 2556x1179 (landscape)
#         6.3" -> 1206x2622 (portrait) / 2622x1206 (landscape)
#         6.9" -> 1320x2868 (portrait) / 2868x1320 (landscape)
#         13"  -> 2048x2732 (portrait) / 2732x2048 (landscape), iPad
#   -m  pad     fit whole image, fill the rest with -b color (default)
#       crop    fill the frame, center-crop the overflow
#       stretch force exact size (distorts)
#   -b  pad color, ffmpeg color name or 0xRRGGBB (default black)
#   -o  output dir (default: <input_dir>/apple-out)
#
# Orientation is detected per image (width > height = landscape).
# Output is always PNG without alpha channel, as App Store Connect requires.

set -euo pipefail

SIZE=6.9
MODE=pad
BG=black
OUT=""

while getopts "s:m:b:o:h" opt; do
  case "$opt" in
    s) SIZE="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    b) BG="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    h|*) sed -n '2,19p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

IN="${1:-.}"
OUT="${OUT:-$IN/apple-out}"

case "$SIZE" in
  6.1) SHORT=1179; LONG=2556 ;;
  6.3) SHORT=1206; LONG=2622 ;;
  6.9) SHORT=1320; LONG=2868 ;;
  13)  SHORT=2048; LONG=2732 ;;
  *) echo "Unknown size: $SIZE (use 6.1, 6.3, 6.9 or 13)" >&2; exit 1 ;;
esac

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 1; }

mkdir -p "$OUT"

count=0
while IFS= read -r -d '' f; do
  dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$f")
  w=${dims%,*}
  h=${dims#*,}

  if [ "$w" -gt "$h" ]; then
    W=$LONG; H=$SHORT
  else
    W=$SHORT; H=$LONG
  fi

  case "$MODE" in
    pad)     vf="scale=${W}:${H}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=${BG}" ;;
    crop)    vf="scale=${W}:${H}:force_original_aspect_ratio=increase:flags=lanczos,crop=${W}:${H}" ;;
    stretch) vf="scale=${W}:${H}:flags=lanczos" ;;
    *) echo "Unknown mode: $MODE (use pad, crop or stretch)" >&2; exit 1 ;;
  esac
  vf="${vf},setsar=1,format=rgb24"

  base=$(basename "${f%.*}")
  ffmpeg -nostdin -v error -y -i "$f" -vf "$vf" -frames:v 1 -update 1 "$OUT/${base}.png"
  echo "ok  ${w}x${h} -> ${W}x${H}  ${base}.png"
  count=$((count + 1))
done < <(find "$IN" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0 | sort -z)

echo "Done: $count image(s) in $OUT"

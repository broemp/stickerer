#!/usr/bin/env bash
# make-screenshots.sh - App Store screenshots and preview videos from the simulator.
#
# Usage: ./make-screenshots.sh [--no-build] [--no-shots] [--no-video] [--no-frame] [name ...]
#
# Everything it captures (screens, captions, devices, locales, the video tour) is set in
# screenshots.conf next to this script. Any value there can be overridden per run:
#   DEVICES=ipad ./make-screenshots.sh --no-video
#   LOCALES="en-US de-DE" ./make-screenshots.sh
#   ./make-screenshots.sh --no-video 01-dashboard shoes   # only these (file name or screen)
#
#   1. Builds the Debug app once (skip with --no-build).
#   2. Per device, on a clean simulator: records the preview video (skip with --no-video)
#      and captures each screenshot by launching the app with `-screenshot "<scene>"`
#      (skip with --no-shots). The app shows offline demo stickers (make-demo-stickers.sh),
#      so there is no account, network or WhatsApp involved.
#   3. Frames the screenshots with fastlane frameit (bezel, caption, background) and
#      exports exact App Store sizes (skip with --no-frame).
#
# Output: appstore-frames/output/<locale>/{iphone-6.9,iphone-6.3,ipad-13}/*.png and previews/<locale>/preview-<device>.mp4

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$HERE")"
FRAMES_DIR="$HERE/appstore-frames"
RAW_DIR="$FRAMES_DIR/fastlane/screenshots"
PREVIEW_DIR="$HERE/previews"
BUNDLE_ID="me.broe.stickerer"

BUILD=1 SHOTS=1 VIDEO=1 FRAME=1
ONLY=()
for arg in "$@"; do
  case "$arg" in
  --no-build) BUILD=0 ;;
  --no-shots) SHOTS=0 FRAME=0 ;;
  --no-video) VIDEO=0 ;;
  --no-frame) FRAME=0 ;;
  -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
  *) ONLY+=("$arg") ;;
  esac
done

# shellcheck source=screenshots.conf
. "$HERE/screenshots.conf"

# Simulator apps can read the host filesystem, so the demo stickers are passed by path
# (read by Stickerer/ScreenshotMode.swift).
DEMO_DIR="$HERE/.build/demo-stickers"
"$HERE/make-demo-stickers.sh" "$DEMO_DIR"
export SIMCTL_CHILD_STICKERER_DEMO_DIR="$DEMO_DIR"

# simctl needs full Xcode, not the Command Line Tools.
if ! xcrun --find simctl >/dev/null 2>&1; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

trim() { sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$1"; }
field() { trim "$(cut -d'|' -f"$2" <<<"$1")"; } # field <screen entry> <1=name|2=caption|3=steps>

# --- Devices -------------------------------------------------------------------
device_sim_name() { case "$1" in iphone) echo "Stickerer Screenshots iPhone" ;; ipad) echo "Stickerer Screenshots iPad" ;; esac; }
device_sim_type() { case "$1" in iphone) echo "$IPHONE_SIM_TYPE" ;; ipad) echo "$IPAD_SIM_TYPE" ;; esac; }
device_suffix() { case "$1" in iphone) echo "" ;; ipad) echo "-ipad" ;; esac; }
# App Store app preview size (portrait).
device_preview_size() { case "$1" in iphone) echo "886x1920" ;; ipad) echo "1200x1600" ;; esac; }

# Prints "<udid> <device type id>" of the simulator called $1 on the newest iOS runtime.
find_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
version = lambda runtime: [int(n) for n in re.findall(r"\d+", runtime.split(".")[-1])]
for runtime in sorted(devices, key=version, reverse=True):
    for device in devices[runtime]:
        if device["name"] == sys.argv[1]:
            print(device["udid"], device["deviceTypeIdentifier"]); sys.exit()
' "$1"
}

# Device -> UDID of a booted clean simulator (no Apple Account, so no account prompts in shots).
# Recreated when its model no longer matches the configured one.
boot_device() {
  local name type type_id found udid runtime
  name=$(device_sim_name "$1")
  type=$(device_sim_type "$1")
  found=$(find_device "$name")
  udid="${found%% *}"
  type_id=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
print(next((t["identifier"] for t in json.load(sys.stdin)["devicetypes"] if t["name"] == sys.argv[1]), ""))
' "$type")
  [ -z "$type_id" ] && { echo "Unknown simulator model '$type' (see: xcrun simctl list devicetypes)" >&2; exit 1; }
  if [ -n "$udid" ] && [ "${found#* }" != "$type_id" ]; then
    echo "Replacing simulator '$name' with a $type…" >&2
    xcrun simctl delete "$udid"
    udid=""
  fi
  if [ -z "$udid" ]; then
    runtime=$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -t- -k2,2n -k3,3n | tail -1)
    echo "Creating simulator '$name' ($type, $runtime)…" >&2
    udid=$(xcrun simctl create "$name" "$type" "$runtime")
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "$udid"
}

# The status bar (time format, iPad date) follows the simulator's system language, not the
# app's launch arguments, so switch the whole simulator over (reboots it when it changes).
prepare_simulator() { # udid locale
  local udid="$1" locale="$2"
  if [ "$(xcrun simctl spawn "$udid" defaults read -g AppleLocale 2>/dev/null)" != "${locale/-/_}" ]; then
    echo "Switching simulator to $locale…"
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "${locale%%-*}"
    xcrun simctl spawn "$udid" defaults write -g AppleLocale "${locale/-/_}"
    xcrun simctl shutdown "$udid"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
  fi
  xcrun simctl ui "$udid" appearance "$APPEARANCE"
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
}

launch() { # udid locale steps
  xcrun simctl terminate "$1" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$1" "$BUNDLE_ID" -screenshot "$3" \
    -AppleLanguages "(${2%%-*})" -AppleLocale "${2/-/_}" >/dev/null
}

# --- Video ---------------------------------------------------------------------
record_preview() { # device udid locale
  local device="$1" udid="$2" locale="$3" size raw out rec seconds
  size=$(device_preview_size "$device")
  seconds=$(grep -oE 'wait:[[:space:]]*[0-9.]+' <<<"$PREVIEW_STEPS" | grep -oE '[0-9.]+' | paste -sd+ - | bc)
  length=$(bc <<<"$seconds - ${PREVIEW_LEAD:-5}")
  if [ "$(bc <<<"$length < 15 || $length > 30")" = 1 ]; then
    echo "warn  the preview tour is ${length}s (waits minus PREVIEW_LEAD); App Store previews must be 15-30 s" >&2
  fi
  mkdir -p "$PREVIEW_DIR/$locale" "$HERE/.build"
  raw="$HERE/.build/preview-$device.mov"
  out="$PREVIEW_DIR/$locale/preview-$device.mp4"

  launch "$udid" "$locale" "$PREVIEW_STEPS"
  # Start recording once the first screen has loaded, so the video doesn't open on a blank screen.
  sleep "${PREVIEW_LEAD:-5}"
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw" >/dev/null 2>&1 &
  rec=$!
  sleep "$(bc <<<"$seconds - ${PREVIEW_LEAD:-5} + 2")" # the lead ate part of the first wait; the recorder takes a moment to start
  kill -INT "$rec"
  wait "$rec" 2>/dev/null || true
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true

  # App Store app previews: 15-30 s, <= 30 fps, H.264, exact size, stereo AAC audio (silent here).
  ffmpeg -nostdin -v error -y -i "$raw" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -vf "scale=${size%x*}:${size#*x}:force_original_aspect_ratio=increase:flags=lanczos,crop=${size%x*}:${size#*x},fps=30,format=yuv420p,setsar=1" \
    -c:v libx264 -profile:v high -level 4.0 -preset slow -b:v 10M -maxrate 12M -bufsize 20M \
    -c:a aac -b:a 256k -ar 44100 -shortest -t 29.5 -movflags +faststart "$out"
  echo "ok  $device  $locale  $(basename "$out") ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" | cut -c1-4) s)"
}

# --- Screenshots ---------------------------------------------------------------
write_captions() { # locale  -> title.strings for frameit
  local locale="$1" file="$RAW_DIR/$1/title.strings" entry
  if [ -f "$HERE/captions/$locale.strings" ]; then
    cp "$HERE/captions/$locale.strings" "$file"
    return
  fi
  : >"$file"
  for entry in "${SCREENS[@]}"; do
    printf '"%s" = "%s";\n' "$(field "$entry" 1)" "$(field "$entry" 2 | sed 's/"/\\"/g')" >>"$file"
  done
}

capture_screens() { # device udid locale
  local device="$1" udid="$2" locale="$3" suffix out entry name steps first=1 sum previous=""
  suffix=$(device_suffix "$device")
  out="$RAW_DIR/$locale"
  mkdir -p "$out"
  write_captions "$locale"
  if [ ${#ONLY[@]} -eq 0 ]; then # full run: drop this device's old shots, but keep hand-made ones
    if [ -z "$suffix" ]; then
      find "$out" -maxdepth 1 -name '*.png' ! -name '*-ipad*' ! -name '*share*' -delete
    else
      find "$out" -maxdepth 1 -name "*$suffix*.png" ! -name '*share*' -delete
    fi
  fi

  for entry in "${SCREENS[@]}"; do
    name="$(field "$entry" 1)"
    steps="$(field "$entry" 3)"
    [ -z "$steps" ] && continue # hand-made shot
    if [ ${#ONLY[@]} -gt 0 ] && [[ ! " ${ONLY[*]} " =~ " $name " ]] && [[ ! " ${ONLY[*]} " =~ " $steps " ]]; then continue; fi
    launch "$udid" "$locale" "$steps"
    # The first launch after an install is slower (cold start).
    if [ "$first" = 1 ]; then sleep $((SCREEN_WAIT * 2)); first=0; else sleep "$SCREEN_WAIT"; fi
    rm -f "$out/$name${suffix}_framed.png"
    xcrun simctl io "$udid" screenshot --type=png "$out/$name$suffix.png" >/dev/null 2>&1
    if [ "$device" = ipad ]; then
      # frameit only has a bezel for the 2048x2732 iPad Pro screen (also valid for the 13" slot).
      magick "$out/$name$suffix.png" -resize 2048x2732^ -gravity center -extent 2048x2732 "$out/$name$suffix.png"
    fi
    # Two different screens never look exactly alike; identical shots mean an error or
    # spinner was captured (e.g. a failed demo sign-in).
    sum=$(md5 -q "$out/$name$suffix.png")
    if [ "$sum" = "$previous" ]; then
      echo "warn  $device  $locale  $name$suffix is identical to the previous shot; check it" >&2
    fi
    previous="$sum"
    echo "ok  $device  $locale  $name$suffix"
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# --- Run -----------------------------------------------------------------------
open -a "${DEVELOPER_DIR:-$(xcode-select -p)}/Applications/Simulator.app" 2>/dev/null || true

APP_PATH="$HERE/.build/Build/Products/Debug-iphonesimulator/Stickerer.app"
if [ "$BUILD" = 1 ]; then
  echo "Building (Debug)…"
  (cd "$APP_DIR" && xcodegen generate --quiet)
  xcodebuild -project "$APP_DIR/Stickerer.xcodeproj" -scheme Stickerer -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$HERE/.build" -quiet build
fi

for device in $DEVICES; do
  UDID=$(boot_device "$device")
  echo "Simulator: $(xcrun simctl list devices | grep "$UDID" | sed 's/^ *//')"
  if [ "$BUILD" = 1 ] || ! xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
    xcrun simctl install "$UDID" "$APP_PATH"
  fi
  # The pasteboard "Paste" button would otherwise show a system prompt; none of the scenes need it.
  for locale in $LOCALES; do
    prepare_simulator "$UDID" "$locale"
    if [ "$VIDEO" = 1 ]; then record_preview "$device" "$UDID" "$locale"; fi
    if [ "$SHOTS" = 1 ]; then capture_screens "$device" "$UDID" "$locale"; fi
  done
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
done

if [ "$VIDEO" = 1 ]; then echo "Videos: $PREVIEW_DIR/"; fi
if [ "$FRAME" = 1 ]; then
  echo "Framing with fastlane frameit…"
  (cd "$FRAMES_DIR" && fastlane ios all)
  echo "Screenshots: $FRAMES_DIR/output/"
elif [ "$SHOTS" = 1 ]; then
  echo "Raw screenshots: $RAW_DIR/"
fi

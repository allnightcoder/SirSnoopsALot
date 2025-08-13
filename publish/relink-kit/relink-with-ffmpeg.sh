#!/usr/bin/env bash
set -euo pipefail

# Example relink script for visionOS device (adjust as needed for simulator).
# Prereqs:
# - AppObjects.a from extract-app-objects.sh
# - FFmpeg static libs (libavcodec.a, libavformat.a, libavfilter.a, libavutil.a, libswresample.a, libswscale.a)
# - Correct SDK path and framework list

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_DIR="${FFMPEG_DIR:-$SCRIPT_DIR/../sources/build-visionos/ffmpeg-install}"
SDK_NAME="${SDK_NAME:-xros2.1}"
SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CLANG="$(xcrun --sdk "$SDK_NAME" --find clang)"

APP_OBJECTS="${APP_OBJECTS:-$SCRIPT_DIR/AppObjects.a}"
OUT_BIN="${OUT_BIN:-$SCRIPT_DIR/RelinkedAppBinary}"

if [[ ! -f "$APP_OBJECTS" ]]; then
  echo "Missing $APP_OBJECTS. Run extract-app-objects.sh first or set APP_OBJECTS."
  exit 1
fi

LIBS=(
  "$FFMPEG_DIR/lib/libavcodec.a"
  "$FFMPEG_DIR/lib/libavformat.a"
  "$FFMPEG_DIR/lib/libavfilter.a"
  "$FFMPEG_DIR/lib/libavutil.a"
  "$FFMPEG_DIR/lib/libswresample.a"
  "$FFMPEG_DIR/lib/libswscale.a"
)

for L in "${LIBS[@]}"; do
  [[ -f "$L" ]] || { echo "Missing FFmpeg lib: $L"; exit 1; }
done

CFLAGS=(
  -isysroot "$SDK_PATH"
  -target arm64-apple-xros2.1
)

LDFLAGS=(
  -Wl,-dead_strip
  -framework Foundation
  -framework CoreFoundation
  -lz -liconv -lbz2
)

"$CLANG" "${CFLAGS[@]}" -o "$OUT_BIN" \
  "$APP_OBJECTS" \
  "${LIBS[@]}" \
  "${LDFLAGS[@]}"

echo "Relinked app binary at: $OUT_BIN"


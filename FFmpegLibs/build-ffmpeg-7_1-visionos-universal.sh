#!/usr/bin/env bash
set -e

# Paths where the device and simulator builds ended up
DEVICE_LIB_DIR="$(pwd)/build-visionos/ffmpeg-install/lib"
SIMULATOR_LIB_DIR="$(pwd)/build-visionos-simulator/ffmpeg-install/lib"

# Universal output directory
UNIVERSAL_DIR="$(pwd)/build-visionos-universal"
UNIVERSAL_LIB_DIR="$UNIVERSAL_DIR/ffmpeg-install/lib"
UNIVERSAL_INCLUDE_DIR="$UNIVERSAL_DIR/ffmpeg-install/include"

# Clean any existing universal directory
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_LIB_DIR"

# Copy includes (they should be identical from device or simulator builds)
cp -r "$(pwd)/build-visionos/ffmpeg-install/include" "$UNIVERSAL_DIR/ffmpeg-install"

# List the typical FFmpeg static libs you want to combine
LIBS=(
  libavcodec
  libavdevice
  libavfilter
  libavformat
  libavresample
  libavutil
  libpostproc
  libswresample
  libswscale
)

echo "Merging FFmpeg device + simulator builds..."

for LIB in "${LIBS[@]}"; do
  DEVICE_FILE="$DEVICE_LIB_DIR/${LIB}.a"
  SIM_FILE="$SIMULATOR_LIB_DIR/${LIB}.a"

  # If the library was not built (e.g. you disabled avdevice), skip
  if [[ ! -f "$DEVICE_FILE" || ! -f "$SIM_FILE" ]]; then
    echo "Skipping $LIB (not found in one of the builds)."
    continue
  fi

  OUTPUT_FILE="$UNIVERSAL_LIB_DIR/${LIB}.a"

  echo "Creating universal $LIB"
  lipo -create "$DEVICE_FILE" "$SIM_FILE" -output "$OUTPUT_FILE"
  lipo -info "$OUTPUT_FILE"
done

echo "Universal FFmpeg libs created at: $UNIVERSAL_LIB_DIR"

#!/usr/bin/env bash
set -e

#######################################
# Enforce using the correct Xcode
#######################################
# If needed, force Xcode selection:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

#######################################
# Paths to built libraries
#######################################
# Device build output
DEVICE_LIB_DIR="$(pwd)/build-visionos/ffmpeg-install/lib"
DEVICE_INCLUDE_DIR="$(pwd)/build-visionos/ffmpeg-install/include"

# Simulator build output
SIM_LIB_DIR="$(pwd)/build-visionos-simulator/ffmpeg-install/lib"
SIM_INCLUDE_DIR="$(pwd)/build-visionos-simulator/ffmpeg-install/include"

# Output directory for XCFrameworks
XCFRAMEWORK_OUTPUT="$(pwd)/build-visionos-xcframework"
rm -rf "$XCFRAMEWORK_OUTPUT"
mkdir -p "$XCFRAMEWORK_OUTPUT"

#######################################
# The libraries we want to package
#######################################
LIBS=(
  libavcodec
  libavfilter
  libavformat
  libavutil
  libswresample
  libswscale
  # Add others if you built them
)

#######################################
# Create an XCFramework for each library
#######################################
for LIB in "${LIBS[@]}"; do
  DEVICE_LIB="$DEVICE_LIB_DIR/${LIB}.a"
  SIM_LIB="$SIM_LIB_DIR/${LIB}.a"

  # Skip if not present
  if [[ ! -f "$DEVICE_LIB" ]]; then
    echo "Warning: Device library not found for $LIB, skipping..."
    continue
  fi
  if [[ ! -f "$SIM_LIB" ]]; then
    echo "Warning: Simulator library not found for $LIB, skipping..."
    continue
  fi

  # We'll store the XCFramework in a subfolder
  OUT_XCFRAMEWORK="$XCFRAMEWORK_OUTPUT/${LIB}.xcframework"

  echo "Creating XCFramework for $LIB"

  # We specify -library (device) + -headers (device include) then (sim) + (sim include)
  # The same headers can be used for both slices, but we pass them explicitly for each
  xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" \
    -headers "$DEVICE_INCLUDE_DIR" \
    -library "$SIM_LIB" \
    -headers "$SIM_INCLUDE_DIR" \
    -output "$OUT_XCFRAMEWORK"
done

echo "All XCFrameworks created in: $XCFRAMEWORK_OUTPUT"

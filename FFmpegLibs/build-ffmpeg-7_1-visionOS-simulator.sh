#!/usr/bin/env bash
set -e

#######################################
# Enforce using the correct Xcode
#######################################
# Only do this if needed:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

#######################################
# Configuration
#######################################
SOURCE="$(pwd)"
BUILD_DIR="$SOURCE/build-visionos-simulator"
PREFIX_DIR="$BUILD_DIR/ffmpeg-install"

ARCH="arm64"
MIN_VERSION="2.1"

# For simulator: "xrsimulator2.1" per 'xcodebuild -showsdks'
SDK_NAME="xrsimulator2.1"
SDK_PATH="$(xcrun --sdk $SDK_NAME --show-sdk-path)"
CC="$(xcrun --sdk $SDK_NAME --find clang)"

CFLAGS="-target arm64-apple-xros-simulator$MIN_VERSION \
        -arch $ARCH \
        -isysroot $SDK_PATH \
        -I$SDK_PATH/usr/include \
        -F$SDK_PATH/System/Library/Frameworks"

LDFLAGS="-target arm64-apple-xros-simulator$MIN_VERSION \
         -arch $ARCH \
         -isysroot $SDK_PATH \
         -L$SDK_PATH/usr/lib \
         -F$SDK_PATH/System/Library/Frameworks \
         -framework Foundation \
         -framework CoreFoundation"

#######################################
# Clean and Create build directories
#######################################
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$PREFIX_DIR"

#######################################
# Configure FFmpeg
#######################################
cd "$BUILD_DIR"

"$SOURCE/configure" \
  --prefix="$PREFIX_DIR" \
  --arch="$ARCH" \
  --target-os=darwin \
  --enable-cross-compile \
  --cc="$CC" \
  --as="$CC" \
  --sysroot="$SDK_PATH" \
  --extra-cflags="$CFLAGS" \
  --extra-ldflags="$LDFLAGS" \
  --enable-static \
  --disable-shared \
  --disable-debug \
  --disable-programs \
  --disable-doc \
  --enable-pic \
  --disable-avdevice \
  --disable-postproc \
  --disable-swscale-alpha \
  --disable-videotoolbox \
  --enable-network \
  --enable-protocol=rtp \
  --enable-protocol=rtsp \
  --enable-protocol=tcp \
  --enable-protocol=udp \
  --enable-demuxer=rtsp \
  --enable-avformat \
  --enable-avcodec \
  --enable-swresample \
  --enable-swscale \
  --enable-avfilter \
  --enable-avutil

#######################################
# Build & Install
#######################################
make -j"$(sysctl -n hw.ncpu)"
make install

echo "Simulator build of FFmpeg installed to: $PREFIX_DIR"

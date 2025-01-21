#!/usr/bin/env bash

# Exit if any command fails
set -e

##################################################
# Configuration
##################################################

# Where FFmpeg source is located (this script assumes you run it from the top-level FFmpeg folder).
SOURCE="$(pwd)"

# Where to place build artifacts
BUILD_DIR="$SOURCE/build-visionos"

# The prefix (installation) directory
PREFIX_DIR="$BUILD_DIR/ffmpeg-install"

# Target architecture (visionOS is arm64 only at the moment)
ARCH="arm64"

# Minimum deployment version for visionOS (adjust if needed)
MIN_VERSION="2.1"

# Platform path for visionOS
PLATFORM_PATH="$(xcrun --sdk xros --show-sdk-platform-path)"
SDK_PATH="$(xcrun --sdk xros --show-sdk-path)"
CC="$(xcrun --sdk xros --find clang)"

# Additional flags passed to the compiler
CFLAGS="-target arm64-apple-xros$MIN_VERSION \
        -arch $ARCH \
        -isysroot $SDK_PATH \
        -I$SDK_PATH/usr/include \
        -F$SDK_PATH/System/Library/Frameworks"

LDFLAGS="-target arm64-apple-xros$MIN_VERSION \
         -arch $ARCH \
         -isysroot $SDK_PATH \
         -L$SDK_PATH/usr/lib \
         -F$SDK_PATH/System/Library/Frameworks \
         -framework Foundation \
         -framework CoreFoundation"

##################################################
# Clean / Create build directories
##################################################
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$PREFIX_DIR"

##################################################
# Configure FFmpeg
##################################################
cd "$BUILD_DIR"

# Example configuration. Adjust to your needs:
# --enable-cross-compile is crucial when building for a different target OS/arch.
# --disable-everything / --enable-whatever to control which components are built.
# If you want shared libs, use --enable-shared (you'll have to handle dynamic frameworks).
# If you only want static libs, stick to --enable-static --disable-shared.
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

# Explanation of some flags:
# - disable-programs: skip building FFmpeg command-line tools (ffmpeg, ffprobe, etc.), 
#   because you typically just need libraries in an app.
# - disable-network: if you plan to do networking (RTSP, etc.), consider removing --disable-network or enabling it. 
#   You might also need --enable-protocol=rtp --enable-protocol=tcp --enable-protocol=udp, etc.
# - enable-avformat/avcodec/swresample...: key libs for decoding/encoding. 
#   Tweak these if you want fewer or more components.

##################################################
# Build & Install
##################################################
make -j$(sysctl -n hw.ncpu)
make install

# The result should be in $PREFIX_DIR (include headers + lib*.a files).

echo "FFmpeg has been built and installed to: $PREFIX_DIR"


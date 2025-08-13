#!/usr/bin/env bash
set -euo pipefail

# This script collects the app’s compiled object files and packages them
# into a single static archive AppObjects.a suitable for relinking with
# replacement FFmpeg static libraries.

BUILD_DIR="${BUILD_DIR:-$(pwd)/../..}"
CONFIGURATION="${CONFIGURATION:-Release}"
SDK="${SDK:-xros}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"

echo "Collecting .o files from DerivedData..."
OBJ_ROOT=$(find "$DERIVED_DATA" -type d -name "Objects-normal" | head -n1 || true)
if [[ -z "${OBJ_ROOT}" ]]; then
  echo "Could not locate Xcode object files. Build the app once in Xcode first."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

find "$OBJ_ROOT" -type f -name "*.o" -print0 | xargs -0 -I{} cp -v {} "$TMP_DIR"/

echo "Creating AppObjects.a"
libtool -static -o "$OUTPUT_DIR/AppObjects.a" "$TMP_DIR"/*.o
echo "Wrote: $OUTPUT_DIR/AppObjects.a"


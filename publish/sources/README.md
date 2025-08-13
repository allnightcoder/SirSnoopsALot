# FFmpeg Sources and Build Scripts

Place the FFmpeg source code that corresponds to the shipped version here (e.g., `publish/sources/ffmpeg/`).

Provided scripts:
- `build-ffmpeg-7_1-visionos.sh`
- `build-ffmpeg-7_1-visionos-simulator.sh`
- `build-ffmpeg-7_1-visionos-xcframework.sh`

Notes:
- These scripts target visionOS device and simulator and package static XCFrameworks.
- They are configured for LGPL-only builds (no `--enable-gpl`, no `--enable-nonfree`).
- Adjust SDK names and versions to match your installed Xcode.

After building:
- Package libraries as XCFrameworks and integrate into Xcode as shown in the project settings.
- Publish this folder along with the exact FFmpeg sources to comply with LGPL.


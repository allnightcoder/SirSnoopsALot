# Relink Kit for SirSnoopsALot (FFmpeg LGPL Compliance)

This folder provides instructions and templates to relink the app with a user-modified FFmpeg build, to satisfy the LGPL v2.1+ requirement when distributing statically linked binaries on visionOS.

What this kit provides:
- Guidance to rebuild FFmpeg with your changes.
- A template script to assemble your app object files into a single static archive (`AppObjects.a`).
- A template script to relink the app against replacement FFmpeg static libraries.

High-level steps:
1) Build FFmpeg for visionOS (device + simulator) with your desired changes. See `../sources` for our build scripts.
2) Build the app once in Xcode to generate object files.
3) Run `extract-app-objects.sh` to collect app object files into `AppObjects.a` (or supply your own `AppObjects.a`).
4) Run `relink-with-ffmpeg.sh` to produce a new app binary using your FFmpeg static libs.

Notes and limitations:
- Code signing and App Store deployment are subject to Apple’s rules. This kit’s goal is LGPL relinkability, not redistributing a signed, store-ready build.
- You may need to adjust paths and SDK versions to match your local Xcode setup.
- This kit does not include FFmpeg source; see `../sources` for where to put it.

Files in this folder:
- `NOTICE.txt`: Overview and responsibilities.
- `extract-app-objects.sh`: Collect app object files into `AppObjects.a`.
- `relink-with-ffmpeg.sh`: Example relink step using `ld`/`clang`.


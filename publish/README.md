# Publish Assets for FFmpeg Compliance

This folder contains materials to satisfy LGPL obligations when distributing this app with statically linked FFmpeg for visionOS.

Structure:
- `sources/`: Build scripts and (user-supplied) FFmpeg source tree to reproduce the shipped libraries.
- `relink-kit/`: Instructions and scripts to relink the app with a user-modified FFmpeg build (LGPL relinkability).

How to use:
1) Place the FFmpeg source (matching the shipped version) under `sources/ffmpeg/` (or any sibling path you prefer) and use the provided build scripts.
2) Publish this folder (or a link to it) so users can access scripts and relink materials.

See the top-level `ATTRIBUTIONS.md` for license texts and attributions.


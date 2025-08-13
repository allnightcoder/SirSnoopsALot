# Third-Party Attributions

## FFmpeg
- Project: FFmpeg (https://ffmpeg.org)
- License: GNU Lesser General Public License v2.1 or later (LGPL v2.1+)
- Source: We provide build scripts and will publish the exact FFmpeg source used under `publish/sources`. The FFmpeg source corresponding to shipped binaries will be made available alongside releases.

### License Text
The full text of the LGPL v2.1 is included at `licenses/LGPL-2.1.txt`.

### Relinkability
This app statically links FFmpeg. To satisfy LGPL’s relinking requirement, we provide a relink kit at `publish/relink-kit` which allows replacing the FFmpeg libraries with a user-modified version and relinking the app object code.

If you have questions about licensing, please contact the maintainers of this repository.


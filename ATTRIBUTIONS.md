# Third-Party Attributions

## FFmpeg
- **Project**: FFmpeg (https://ffmpeg.org)
- **Version**: FFmpeg 7.1 (unmodified)
- **Released**: 2024-09-29
- **License**: GNU Lesser General Public License v2.1 or later (LGPL v2.1+)
- **Official Source**: https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz
- **SHA256**: `40973d44970dbc83ef302b0609f2e74982be2d85916dd2ee7472d30678a7abe6`

### Source Code Availability
This application uses the complete, unmodified FFmpeg 7.1 source code. The source is available at the official FFmpeg URL above.

**Written Offer** (valid for 3 years from release date): If you are unable to obtain the FFmpeg 7.1 source code from the official FFmpeg website, please contact the maintainers of this repository via GitHub issues, and we will provide the complete source code at no charge beyond the cost of physically performing source distribution.

Build scripts for compiling FFmpeg 7.1 for visionOS are included in this repository at `publish/sources/`.

### License Text
The full text of the LGPL v2.1 is included at `licenses/LGPL-2.1.txt`.

### Relinkability
This app statically links FFmpeg. To satisfy LGPL's relinking requirement, we provide a relink kit at `publish/relink-kit` which allows replacing the FFmpeg libraries with a user-modified version and relinking the app object code.

If you have questions about licensing, please contact the maintainers of this repository.


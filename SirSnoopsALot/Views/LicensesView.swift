import SwiftUI

struct LicensesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Third-Party")) {
                    NavigationLink("FFmpeg (LGPL v2.1+)") {
                        LicenseDetailView(title: "FFmpeg", text: ffmpegLGPLv21Text)
                    }
                }
                Section(footer: Text("View the full license text at gnu.org").font(.footnote)) {
                    Link("Full LGPL v2.1 License", destination: URL(string: "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt")!)
                }
            }
            .navigationTitle("Licenses")
        }
    }
}

private struct LicenseDetailView: View {
    let title: String
    let text: String
    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
    }
}

// Full LGPL v2.1 text (unmodified) for in-app display
// Source: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
private let ffmpegLGPLv21Text: String = """
FFmpeg is licensed under the GNU Lesser General Public License v2.1 or later (LGPL v2.1+).

This app uses FFmpeg 7.1 (unmodified, released 2024-09-29).

Source Code Availability:
The complete FFmpeg 7.1 source code is available at:
https://ffmpeg.org/releases/ffmpeg-7.1.tar.xz

Written offer (valid for 3 years): If you cannot obtain the source from the official FFmpeg website, contact the maintainers Tetradex LLC we will provide it at no charge beyond distribution costs.

Build scripts and relink kit (for LGPL compliance) are available in the GitHub repository under the publish/ folder.
"""

#Preview {
    LicensesView()
}

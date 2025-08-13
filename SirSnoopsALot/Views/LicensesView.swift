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
                Section(footer: Text("Sources and relink kit are available in the app repository under the publish/ folder.").font(.footnote)) {
                    Link("Full LGPL v2.1 text (gnu.org)", destination: URL(string: "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt")!)
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

This app statically links FFmpeg and provides:
- Attribution in-app and in the repository.
- Source code and build scripts under `publish/sources`.
- A relink kit under `publish/relink-kit` to satisfy the LGPL relinking requirement.

For the full license text, tap the link below.
"""

#Preview {
    LicensesView()
}

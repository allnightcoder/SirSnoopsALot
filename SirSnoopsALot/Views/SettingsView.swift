import SwiftUI

struct SettingsView: View {
    @AppStorage("showCameraFeedBorder") private var showCameraFeedBorder = false
    @AppStorage("showFloatingControls") private var showFloatingControls = false
    @AppStorage("showTimelineScrubPreview") private var showTimelineScrubPreview = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Tasteful Red Border", isOn: $showCameraFeedBorder)
                    Toggle("Floating Window Controls", isOn: $showFloatingControls)
                }

                Section("Historical Playback") {
                    Toggle("Timeline Scrub Preview", isOn: $showTimelineScrubPreview)
                }

                Section {
                    NavigationLink("Licenses") {
                        LicensesView()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let defaults = UserDefaults.standard
    defaults.set(false, forKey: "showCameraFeedBorder")
    return SettingsView()
}

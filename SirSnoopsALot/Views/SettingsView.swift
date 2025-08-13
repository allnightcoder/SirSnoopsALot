import SwiftUI

struct SettingsView: View {
    @AppStorage("showCameraFeedBorder") private var showCameraFeedBorder = false
    @AppStorage("showFloatingControls") private var showFloatingControls = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Tasteful Red Border", isOn: $showCameraFeedBorder)
                Toggle("Floating Window Controls", isOn: $showFloatingControls)
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

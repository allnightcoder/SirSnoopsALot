import SwiftUI

struct SettingsView: View {
    @AppStorage("showCameraFeedBorder") private var showCameraFeedBorder = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Tasteful Red Border", isOn: $showCameraFeedBorder)
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
    SettingsView()
} 
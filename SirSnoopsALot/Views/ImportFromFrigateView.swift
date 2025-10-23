import SwiftUI

struct ImportFromFrigateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = FrigateImporter()

    // Connection settings
    @State private var frigateHost: String = ""
    @State private var frigatePort: String = "5000"
    @State private var useHTTPS: Bool = false

    // Authentication (optional)
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showAuthSection: Bool = false

    // UI state
    @State private var showCameraList: Bool = false
    @State private var showImportResult: Bool = false
    @State private var importResultMessage: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if showCameraList {
                    cameraSelectionView
                } else {
                    connectionFormView
                }
            }
            .navigationTitle("Import from Frigate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Import Complete", isPresented: $showImportResult) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(importResultMessage)
            }
        }
    }

    // MARK: - Connection Form (Step 1)

    private var connectionFormView: some View {
        Form {
            Section {
                TextField("Frigate Host", text: $frigateHost)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.done)

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $frigatePort)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Toggle("Use HTTPS", isOn: $useHTTPS)
            } header: {
                Text("Frigate Server Settings")
            } footer: {
                Text("Enter your Frigate NVR server address (e.g., 192.168.1.100)")
            }

            Section {
                DisclosureGroup("Authentication (Optional)", isExpanded: $showAuthSection) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            } footer: {
                Text("Required for Frigate instances with authentication enabled")
            }

            if let errorMessage = importer.errorMessage {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button(action: connectToFrigate) {
                    HStack {
                        if importer.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text(importer.isLoading ? "Connecting..." : "Connect to Frigate")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(frigateHost.isEmpty || importer.isLoading)
            }
        }
    }

    // MARK: - Camera Selection (Step 2)

    private var cameraSelectionView: some View {
        VStack(spacing: 0) {
            // Camera list
            List {
                ForEach(importer.discoveredCameras.indices, id: \.self) { index in
                    cameraRow(for: $importer.discoveredCameras[index])
                }
            }

            // Bottom action bar
            VStack(spacing: 12) {
                Divider()

                HStack {
                    Button("Back") {
                        showCameraList = false
                    }

                    Spacer()

                    Text("\(selectedCameraCount) selected")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: importSelectedCameras) {
                        Text("Import (\(selectedCameraCount))")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCameraCount == 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.regularMaterial)
        }
    }

    private func cameraRow(for camera: Binding<FrigateCameraImportable>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: {
                if camera.wrappedValue.canImport {
                    camera.wrappedValue.isSelected.toggle()
                }
            }) {
                Image(systemName: camera.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(camera.wrappedValue.isSelected ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!camera.wrappedValue.canImport)

            // Camera info
            VStack(alignment: .leading, spacing: 6) {
                Text(camera.wrappedValue.name)
                    .font(.headline)

                if let mainUrl = camera.wrappedValue.mainStreamUrl {
                    streamUrlLabel("HD", url: mainUrl)
                }

                if let subUrl = camera.wrappedValue.subStreamUrl {
                    streamUrlLabel("SD", url: subUrl)
                } else if camera.wrappedValue.mainStreamUrl != nil {
                    Text("SD: (will use HD stream)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if let warning = camera.wrappedValue.warningMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text(warning)
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(camera.wrappedValue.canImport ? 1.0 : 0.5)
    }

    private func streamUrlLabel(_ label: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label + ":")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(obfuscateUrl(url))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Helper Properties

    private var selectedCameraCount: Int {
        importer.discoveredCameras.filter { $0.isSelected && $0.canImport }.count
    }

    // MARK: - Actions

    private func connectToFrigate() {
        guard let port = Int(frigatePort) else {
            importer.errorMessage = "Invalid port number"
            return
        }

        Task {
            await importer.fetchCameras(
                host: frigateHost,
                port: port,
                useHTTPS: useHTTPS,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )

            // If successful, show camera list
            if !importer.discoveredCameras.isEmpty {
                showCameraList = true
            }
        }
    }

    private func importSelectedCameras() {
        let result = importer.importCameras(importer.discoveredCameras)
        importResultMessage = result.friendlyMessage
        showImportResult = true
    }

    // MARK: - Utility Functions

    /// Obfuscates credentials in RTSP URLs for display
    private func obfuscateUrl(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let user = url.user else {
            return urlString
        }

        // Replace credentials with asterisks
        var obfuscated = urlString
        if let password = url.password {
            obfuscated = obfuscated.replacingOccurrences(of: "\(user):\(password)@", with: "\(user):****@")
        }
        return obfuscated
    }
}

#Preview {
    ImportFromFrigateView()
}

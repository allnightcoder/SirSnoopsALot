import SwiftUI

struct ImportFromFrigateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = FrigateImporter()

    // Connection settings
    @State private var frigateUrl: String = ""

    // Authentication (optional)
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showAuthSection: Bool = false

    // SSL settings (optional)
    @State private var ignoreSSLErrors: Bool = false
    @State private var showSSLSection: Bool = false

    // go2rtc settings (optional)
    @State private var go2rtcPublicUrl: String = ""
    @State private var showGo2rtcSection: Bool = false

    // UI state
    @State private var showCameraList: Bool = false
    @State private var showImportResult: Bool = false
    @State private var importResultMessage: String = ""

    // UserDefaults keys for persistence
    private let frigateUrlKey = "frigate_last_url"
    private let frigateUsernameKey = "frigate_last_username"
    private let frigateGo2rtcUrlKey = "frigate_last_go2rtc_url"
    private let frigateIgnoreSSLKey = "frigate_last_ignore_ssl"

    // Computed property to check if password is missing when username exists
    private var passwordMissing: Bool {
        !username.isEmpty && password.isEmpty
    }

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
            .onAppear {
                loadSavedSettings()
            }
        }
    }

    // MARK: - Connection Form (Step 1)

    private var connectionFormView: some View {
        Form {
            Section {
                TextField("Frigate URL", text: $frigateUrl)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .keyboardType(.URL)
            } header: {
                Text("Frigate Server")
            } footer: {
                Text("Enter your Frigate server URL (e.g., http://192.168.1.100:5000, https://frigate.example.com)")
            }

            Section {
                DisclosureGroup("Authentication (Optional)", isExpanded: $showAuthSection) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    if passwordMissing {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Password required when username is provided")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            } footer: {
                Text("Required for Frigate instances with authentication enabled")
            }

            Section {
                DisclosureGroup("SSL Settings (Optional)", isExpanded: $showSSLSection) {
                    Toggle("Ignore SSL Certificate Errors", isOn: $ignoreSSLErrors)

                    if ignoreSSLErrors {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("SSL certificate validation disabled. Only use this for trusted servers with self-signed or expired certificates.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            } footer: {
                Text("Enable this option if your Frigate server uses a self-signed or expired SSL certificate")
            }

            Section {
                DisclosureGroup("go2rtc Public URL (Optional)", isExpanded: $showGo2rtcSection) {
                    TextField("Public go2rtc base URL", text: $go2rtcPublicUrl)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                }
            } footer: {
                Text("If using go2rtc restreams, enter the public URL (e.g., rtsp://frigate.example.com:8554). This replaces 127.0.0.1:8554 for remote access.")
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
                .disabled(frigateUrl.isEmpty || importer.isLoading)
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
        // Parse the Frigate URL
        guard let (host, explicitPort, explicitHTTPS) = parseFrigateUrl(frigateUrl) else {
            importer.errorMessage = "Invalid Frigate URL. Please enter a hostname or URL like 'frigate.example.com' or 'http://192.168.1.100:5000'"
            return
        }

        // Save settings (except password)
        saveSettings()

        Task {
            // Pass explicit port/protocol if specified, nil for auto-detect
            await importer.fetchCameras(
                host: host,
                port: explicitPort,
                useHTTPS: explicitHTTPS,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password,
                go2rtcPublicUrl: go2rtcPublicUrl.isEmpty ? nil : go2rtcPublicUrl,
                ignoreSSLErrors: ignoreSSLErrors
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

    /// Parses a Frigate URL and extracts host with optional explicit port/protocol
    /// - Parameter urlString: URL entered by user (e.g., "frigate.example.com", "http://192.168.1.100:5000", "https://frigate.example.com")
    /// - Returns: Tuple of (host, explicitPort, explicitHTTPS) or nil if invalid
    ///   - host: The hostname or IP address
    ///   - explicitPort: Port number if user specified it, nil for auto-detect
    ///   - explicitHTTPS: true/false if user specified protocol, nil for auto-detect
    private func parseFrigateUrl(_ urlString: String) -> (host: String, explicitPort: Int?, explicitHTTPS: Bool?)? {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)

        // Check if user explicitly specified protocol
        let hadProtocol = trimmed.contains("://")

        // Prepare URL for parsing
        var urlToParse = trimmed
        if !hadProtocol {
            // Add temporary protocol for parsing (will not use it)
            urlToParse = "http://\(trimmed)"
        }

        guard let url = URL(string: urlToParse) else {
            return nil
        }

        // Extract host
        guard let host = url.host, !host.isEmpty else {
            return nil
        }

        // Extract explicit protocol (only if user specified it)
        let explicitHTTPS: Bool?
        if hadProtocol {
            explicitHTTPS = url.scheme?.lowercased() == "https"
        } else {
            explicitHTTPS = nil  // Auto-detect
        }

        // Extract explicit port (only if user specified it)
        let explicitPort = url.port  // nil if not specified

        return (host, explicitPort, explicitHTTPS)
    }

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

    /// Loads saved settings from UserDefaults
    private func loadSavedSettings() {
        frigateUrl = UserDefaults.standard.string(forKey: frigateUrlKey) ?? ""
        username = UserDefaults.standard.string(forKey: frigateUsernameKey) ?? ""
        go2rtcPublicUrl = UserDefaults.standard.string(forKey: frigateGo2rtcUrlKey) ?? ""
        ignoreSSLErrors = UserDefaults.standard.bool(forKey: frigateIgnoreSSLKey)

        // Auto-expand sections if values are present
        if !username.isEmpty {
            showAuthSection = true
        }
        if !go2rtcPublicUrl.isEmpty {
            showGo2rtcSection = true
        }
        if ignoreSSLErrors {
            showSSLSection = true
        }
    }

    /// Saves current settings to UserDefaults (except password)
    private func saveSettings() {
        UserDefaults.standard.set(frigateUrl, forKey: frigateUrlKey)
        UserDefaults.standard.set(username, forKey: frigateUsernameKey)
        UserDefaults.standard.set(go2rtcPublicUrl, forKey: frigateGo2rtcUrlKey)
        UserDefaults.standard.set(ignoreSSLErrors, forKey: frigateIgnoreSSLKey)
    }
}

#Preview {
    ImportFromFrigateView()
}

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
            ZStack {
                if showCameraList {
                    cameraSelectionView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    connectionFormView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showCameraList)
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
        ScrollView {
            VStack(spacing: 24) {
                // Frigate Server Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frigate Server")
                        .font(.headline)
                        .foregroundColor(.primary)

                    TextField("Frigate URL", text: $frigateUrl)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 4)

                    Text("Enter your Frigate server URL (e.g., http://192.168.1.100:5000, https://frigate.example.com)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .hoverEffect()

                // Authentication Section
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { withAnimation { showAuthSection.toggle() } }) {
                        HStack {
                            Image(systemName: "person.badge.key")
                                .font(.title3)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Authentication")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Optional")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(showAuthSection ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if showAuthSection {
                        VStack(spacing: 16) {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)

                            if passwordMissing {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Password required when username is provided")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("Required for Frigate instances with authentication enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .hoverEffect()

                // SSL Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { withAnimation { showSSLSection.toggle() } }) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .font(.title3)
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("SSL Settings")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Optional")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(showSSLSection ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if showSSLSection {
                        VStack(spacing: 16) {
                            Toggle("Ignore SSL Certificate Errors", isOn: $ignoreSSLErrors)
                                .toggleStyle(.switch)

                            if ignoreSSLErrors {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("SSL certificate validation disabled. Only use this for trusted servers with self-signed or expired certificates.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("Enable this option if your Frigate server uses a self-signed or expired SSL certificate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .hoverEffect()

                // go2rtc Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { withAnimation { showGo2rtcSection.toggle() } }) {
                        HStack {
                            Image(systemName: "video.and.waveform")
                                .font(.title3)
                                .foregroundColor(.purple)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("go2rtc Public URL")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Optional")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(showGo2rtcSection ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if showGo2rtcSection {
                        VStack(spacing: 16) {
                            TextField("Public go2rtc base URL", text: $go2rtcPublicUrl)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .submitLabel(.done)
                                .textFieldStyle(.roundedBorder)

                            Text("If using go2rtc restreams, enter the public URL (e.g., rtsp://frigate.example.com:8554). This replaces 127.0.0.1:8554 for remote access.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .hoverEffect()

                // Error Message
                if let errorMessage = importer.errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.primary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // Connect Button
                Button(action: connectToFrigate) {
                    HStack(spacing: 12) {
                        if importer.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title3)
                        }
                        Text(importer.isLoading ? "Connecting..." : "Connect to Frigate")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(frigateUrl.isEmpty || importer.isLoading)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Camera Selection (Step 2)

    private var cameraSelectionView: some View {
        ZStack(alignment: .bottom) {
            // Camera list
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Select Cameras")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(importer.discoveredCameras.count) cameras discovered")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                    // Camera cards
                    ForEach(importer.discoveredCameras.indices, id: \.self) { index in
                        cameraCard(for: $importer.discoveredCameras[index])
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .padding(.bottom, 100) // Space for bottom bar
            }

            // Bottom action bar
            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 20) {
                    Button(action: { withAnimation { showCameraList = false } }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text("\(selectedCameraCount) selected")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: importSelectedCameras) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import (\(selectedCameraCount))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedCameraCount == 0)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(.regularMaterial)
            }
        }
    }

    private func cameraCard(for camera: Binding<FrigateCameraImportable>) -> some View {
        Button(action: {
            if camera.wrappedValue.canImport {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    camera.wrappedValue.isSelected.toggle()
                }
            }
        }) {
            HStack(alignment: .top, spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .fill(camera.wrappedValue.isSelected ? Color.blue : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: camera.wrappedValue.isSelected ? "checkmark" : "video")
                        .font(.title3)
                        .foregroundColor(camera.wrappedValue.isSelected ? .white : .gray)
                }

                // Camera info
                VStack(alignment: .leading, spacing: 12) {
                    // Camera name
                    Text(camera.wrappedValue.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    // Stream URLs
                    VStack(alignment: .leading, spacing: 8) {
                        if let mainUrl = camera.wrappedValue.mainStreamUrl {
                            streamUrlRow("HD Stream", url: mainUrl, color: .blue)
                        }

                        if let subUrl = camera.wrappedValue.subStreamUrl {
                            streamUrlRow("SD Stream", url: subUrl, color: .green)
                        } else if camera.wrappedValue.mainStreamUrl != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                Text("SD will use HD stream")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }

                    // Warning if any
                    if let warning = camera.wrappedValue.warningMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.callout)
                            Text(warning)
                                .font(.callout)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        camera.wrappedValue.isSelected ? Color.blue.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(camera.wrappedValue.isSelected ? 1.0 : 0.98)
            .opacity(camera.wrappedValue.canImport ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!camera.wrappedValue.canImport)
        .hoverEffect()
    }

    private func streamUrlRow(_ label: String, url: String, color: Color) -> some View {
        HStack(spacing: 8) {
            // Quality badge
            Text(label.prefix(2))
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color, in: RoundedRectangle(cornerRadius: 6))

            // URL
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
            withAnimation {
                importer.errorMessage = "Invalid Frigate URL. Please enter a hostname or URL like 'frigate.example.com' or 'http://192.168.1.100:5000'"
            }
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

            // If successful, show camera list with animation
            if !importer.discoveredCameras.isEmpty {
                withAnimation {
                    showCameraList = true
                }
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

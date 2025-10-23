import SwiftUI

/// Wrapper view that handles credentials and initializes the historical view
struct HistoricalFrigateWindowView: View {
    let camera: CameraConfig

    @State private var showingCredentialsSheet = false
    @State private var serverURL: String = "https://frigate-web.virtual-chaos.net"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var store: HistoricalFrigateStore?

    var body: some View {
        Group {
            if let store = store {
                HistoricalFrigateView(store: store)
            } else {
                // Initial state - need credentials
                VStack(spacing: 20) {
                    Image(systemName: "video.badge.checkmark")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("Frigate Historical Playback")
                        .font(.title)

                    Text(camera.name)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Button("Configure Frigate Connection") {
                        showingCredentialsSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .sheet(isPresented: $showingCredentialsSheet) {
                    credentialsSheet
                }
                .onAppear {
                    // Auto-show credentials sheet if not configured
                    showingCredentialsSheet = true
                }
            }
        }
    }

    // MARK: - Credentials Sheet

    private var credentialsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Frigate Server")) {
                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Authentication")) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Text("Enter your Frigate server credentials to view historical recordings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Frigate Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCredentialsSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        connectToFrigate()
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Actions

    private func connectToFrigate() {
        guard let url = URL(string: serverURL) else {
            return
        }

        let credentials = FrigateCredentials(
            username: username,
            password: password,
            serverURL: url
        )

        // Initialize store with credentials
        store = HistoricalFrigateStore(camera: camera, credentials: credentials)
        showingCredentialsSheet = false
    }
}

import SwiftUI
import Combine

/// Wrapper view that handles credentials and initializes the historical view
struct HistoricalFrigateWindowView: View {
    let camera: CameraConfig

    @State private var showingCredentialsSheet = false
    @State private var serverURL: String = "https://frigate-web.virtual-chaos.net"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var store: HistoricalFrigateStore?
    @State private var hasAttemptedAutoConnect = false
    private let savedCredentialsKey = "frigate_history_credentials"

    var body: some View {
        Group {
            if let store = store {
                HistoricalFrigateView(store: store)
                    .onReceive(store.$errors) { errors in
                        guard let last = errors.last else { return }
                        if case .authentication = last {
                            self.store = nil
                            showingCredentialsSheet = true
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Update Credentials") {
                                showingCredentialsSheet = true
                            }
                        }
                    }
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
                .onAppear {
                    if !hasAttemptedAutoConnect && loadSavedCredentials() {
                        hasAttemptedAutoConnect = true
                        connectToFrigate()
                    } else {
                        showingCredentialsSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingCredentialsSheet) {
            credentialsSheet
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

        hasAttemptedAutoConnect = true

        let credentials = FrigateCredentials(
            username: username,
            password: password,
            serverURL: url
        )

        saveCredentials(credentials)

        // Initialize store with credentials
        store = HistoricalFrigateStore(camera: camera, credentials: credentials)
        showingCredentialsSheet = false
    }

    @discardableResult
    private func loadSavedCredentials() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: savedCredentialsKey),
              let saved = try? JSONDecoder().decode(FrigateCredentials.self, from: data),
              !saved.username.isEmpty,
              !saved.password.isEmpty else { return false }
        serverURL = saved.serverURL.absoluteString
        username = saved.username
        password = saved.password
        return true
    }

    private func saveCredentials(_ credentials: FrigateCredentials) {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: savedCredentialsKey)
        }
    }
}

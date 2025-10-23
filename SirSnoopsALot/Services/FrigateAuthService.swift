import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigateAuthService")

@MainActor
class FrigateAuthService: ObservableObject {
    @Published private(set) var currentSession: AuthSession?
    @Published private(set) var isAuthenticating = false

    private let keychainService = "net.virtual-chaos.SirSnoopsALot.frigate"
    private var credentials: FrigateCredentials?

    // MARK: - Public Methods

    /// Login with credentials and obtain JWT token
    func login(credentials: FrigateCredentials) async throws -> AuthSession {
        isAuthenticating = true
        defer { isAuthenticating = false }

        self.credentials = credentials

        // Build login URL
        let loginURL = credentials.serverURL.appendingPathComponent("/api/login")

        // Create request
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        // Create JSON body with "user" field (Frigate's expected field name)
        let loginPayload: [String: String] = ["user": credentials.username, "password": credentials.password]
        request.httpBody = try JSONEncoder().encode(loginPayload)

        // Execute request
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HistoricalFrigateError.authentication("Invalid response from server")
        }

        guard httpResponse.statusCode == 200 else {
            throw HistoricalFrigateError.authentication("Login failed with status \(httpResponse.statusCode)")
        }

        // Extract JWT token from Set-Cookie header
        guard let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie"),
              let tokenRange = setCookie.range(of: "frigate_token="),
              let endRange = setCookie.range(of: ";", range: tokenRange.upperBound..<setCookie.endIndex) else {
            throw HistoricalFrigateError.authentication("No frigate_token found in response")
        }

        let token = String(setCookie[tokenRange.upperBound..<endRange.lowerBound])

        // Create session (estimate token expires in 24 hours, refresh after 23 hours)
        let expiry = Date().addingTimeInterval(24 * 3600)
        let refreshDate = Date().addingTimeInterval(23 * 3600)
        let session = AuthSession(token: token, expiry: expiry, refreshDate: refreshDate)

        // Store session
        currentSession = session
        try storeSessionInKeychain(session)

        logger.info("Successfully authenticated with Frigate server")
        return session
    }

    /// Refresh token if needed
    func refreshIfNeeded() async throws -> AuthSession {
        // If we have a valid session, return it
        if let session = currentSession, Date() < session.refreshDate {
            return session
        }

        // Try to load session from keychain first
        if let storedSession = try loadSessionFromKeychain(), Date() < storedSession.refreshDate {
            currentSession = storedSession
            return storedSession
        }

        // Need to re-authenticate
        guard let credentials = self.credentials else {
            throw HistoricalFrigateError.authentication("No credentials available")
        }

        return try await login(credentials: credentials)
    }

    /// Get authorized request with Bearer token
    func authorizedRequest(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let session = try await refreshIfNeeded()
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Keychain Storage

    private func storeSessionInKeychain(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session",
            kSecValueData as String: data
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to store session in keychain: \(status)")
            throw HistoricalFrigateError.authentication("Failed to store session securely")
        }
    }

    private func loadSessionFromKeychain() throws -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Failed to load session from keychain: \(status)")
            }
            return nil
        }

        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func clearSession() {
        currentSession = nil
        credentials = nil

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session"
        ]

        SecItemDelete(query as CFDictionary)
        logger.info("Cleared session")
    }
}

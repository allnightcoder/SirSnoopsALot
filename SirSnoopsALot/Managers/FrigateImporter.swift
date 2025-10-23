import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigateImporter")

/// Result of importing cameras from Frigate
struct FrigateImportResult {
    let imported: Int
    let skipped: Int
    let total: Int

    var friendlyMessage: String {
        if total == 0 {
            return "No cameras were selected for import."
        }

        if skipped == 0 {
            if imported == 1 {
                return "Successfully imported 1 camera!"
            } else {
                return "Successfully imported \(imported) cameras!"
            }
        } else if imported == 0 {
            if skipped == 1 {
                return "1 camera was skipped because it already exists in your library."
            } else {
                return "All \(skipped) cameras were skipped because they already exist in your library."
            }
        } else {
            // Mixed result
            var message = "Imported \(imported) new camera\(imported == 1 ? "" : "s")."
            if skipped == 1 {
                message += " 1 camera was skipped because it already exists."
            } else {
                message += " \(skipped) cameras were skipped because they already exist."
            }
            return message
        }
    }
}

@MainActor
class FrigateImporter: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var discoveredCameras: [FrigateCameraImportable] = []

    // MARK: - Public Methods

    /// Connects to Frigate NVR and fetches camera configurations
    /// - Parameters:
    ///   - host: Frigate server hostname or IP address
    ///   - port: Frigate API port (default: 5000)
    ///   - useHTTPS: Whether to use HTTPS instead of HTTP
    ///   - username: Optional username for HTTP Basic Authentication
    ///   - password: Optional password for HTTP Basic Authentication
    ///   - go2rtcPublicUrl: Optional public go2rtc base URL (e.g., rtsp://frigate.example.com:8554)
    ///   - ignoreSSLErrors: Whether to ignore SSL certificate validation errors (for self-signed certificates)
    func fetchCameras(host: String, port: Int = 5000, useHTTPS: Bool = false, username: String? = nil, password: String? = nil, go2rtcPublicUrl: String? = nil, ignoreSSLErrors: Bool = false) async {
        guard !host.isEmpty else {
            errorMessage = "Please enter a Frigate host address"
            return
        }

        isLoading = true
        errorMessage = nil
        discoveredCameras = []

        // Build Frigate API URL
        let scheme = useHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/api/config") else {
            errorMessage = "Invalid Frigate server URL"
            isLoading = false
            return
        }

        logger.info("Fetching Frigate config from: \(url.absoluteString)")

        // Determine which auth methods to try
        var authMethodsToTry = determineAuthAttemptOrder(port: port)

        // If no credentials provided, only try .none
        if username == nil || password == nil {
            authMethodsToTry = [.none]
        } else {
            // Check if we have a cached successful method for this host
            if let cachedMethod = getCachedAuthMethod(for: host) {
                // Try cached method first, but keep others as fallback
                authMethodsToTry.removeAll { $0 == cachedMethod }
                authMethodsToTry.insert(cachedMethod, at: 0)
                logger.info("Using cached auth method: \(cachedMethod.rawValue)")
            }
        }

        // Try each auth method until one succeeds
        var lastError: Error?
        var lastStatusCode: Int?

        for authMethod in authMethodsToTry {
            logger.debug("Trying auth method: \(authMethod.rawValue)")

            do {
                // Attempt to fetch config with this auth method
                let (data, _) = try await attemptFetchWithAuth(
                    url: url,
                    authMethod: authMethod,
                    host: host,
                    port: port,
                    useHTTPS: useHTTPS,
                    username: username ?? "",
                    password: password ?? "",
                    ignoreSSLErrors: ignoreSSLErrors
                )

                // Success! Parse the config
                let decoder = JSONDecoder()
                let frigateConfig = try decoder.decode(FrigateConfig.self, from: data)
                let cameras = parseFrigateConfig(frigateConfig, go2rtcPublicUrl: go2rtcPublicUrl)

                if cameras.isEmpty {
                    errorMessage = "No cameras found in Frigate configuration"
                } else {
                    discoveredCameras = cameras
                    logger.info("Successfully discovered \(cameras.count) cameras using \(authMethod.rawValue)")

                    // Cache this successful auth method
                    if username != nil && password != nil {
                        cacheAuthMethod(authMethod, for: host)
                    }
                }

                isLoading = false
                return

            } catch let error as FrigateError {
                if case .httpError(let code) = error {
                    lastStatusCode = code
                    // 401/403 means auth failed, try next method
                    if code == 401 || code == 403 {
                        logger.debug("Auth method \(authMethod.rawValue) failed with \(code), trying next method")
                        lastError = error
                        continue
                    } else {
                        // Other HTTP errors (404, 500, etc.) - fail immediately
                        errorMessage = error.localizedDescription
                        logger.error("Request failed with HTTP \(code): \(error.localizedDescription)")
                        isLoading = false
                        return
                    }
                } else {
                    // Non-HTTP errors (network, invalid response, etc.)
                    lastError = error
                    logger.error("Request failed: \(error.localizedDescription)")
                }
            } catch {
                // Other errors (JSON decode, etc.)
                lastError = error
                logger.error("Unexpected error: \(error.localizedDescription)")
            }
        }

        // All auth methods failed
        if let statusCode = lastStatusCode, (statusCode == 401 || statusCode == 403) {
            // Clear cached method if it exists
            clearCachedAuthMethod(for: host)
            errorMessage = "Authentication failed. Please check your username and password."
        } else if let error = lastError {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
        } else {
            errorMessage = "Failed to connect to Frigate server"
        }

        isLoading = false
    }

    /// Imports selected cameras into CameraManager
    /// - Parameter cameras: List of cameras to import (only selected ones will be imported)
    /// - Returns: Result containing counts of imported and skipped cameras
    func importCameras(_ cameras: [FrigateCameraImportable]) -> FrigateImportResult {
        let cameraManager = CameraManager.shared
        var importCount = 0
        var skippedCount = 0
        var totalSelected = 0

        for camera in cameras where camera.isSelected && camera.canImport {
            totalSelected += 1

            // Use main stream for HD, fallback to main for SD if sub doesn't exist
            let hdUrl = camera.mainStreamUrl ?? ""
            let sdUrl = camera.effectiveSubStreamUrl

            // Check if camera already exists by comparing RTSP URLs
            if cameraExists(highResUrl: hdUrl, lowResUrl: sdUrl, in: cameraManager) {
                logger.info("Skipping camera '\(camera.name)' - already exists with matching RTSP URLs")
                skippedCount += 1
                continue
            }

            cameraManager.addCamera(
                name: camera.name,
                highResUrl: hdUrl,
                lowResUrl: sdUrl,
                description: "Imported from Frigate NVR"
            )
            importCount += 1
        }

        logger.info("Import complete: \(importCount) imported, \(skippedCount) skipped")

        return FrigateImportResult(
            imported: importCount,
            skipped: skippedCount,
            total: totalSelected
        )
    }

    // MARK: - Private Methods

    /// Attempts to login to Frigate and obtain a JWT token
    /// - Parameters:
    ///   - host: Frigate server hostname
    ///   - port: Frigate API port
    ///   - useHTTPS: Whether to use HTTPS
    ///   - username: Username for authentication
    ///   - password: Password for authentication
    ///   - ignoreSSLErrors: Whether to ignore SSL certificate errors
    /// - Returns: JWT token string if login successful, nil otherwise
    private func loginToFrigate(host: String, port: Int, useHTTPS: Bool, username: String, password: String, ignoreSSLErrors: Bool) async -> String? {
        let scheme = useHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/api/login") else {
            logger.error("Invalid login URL")
            return nil
        }

        logger.info("Attempting JWT login to: \(url.absoluteString)")

        // Create login request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create JSON body
        let loginPayload: [String: String] = ["user": username, "password": password]
        guard let jsonData = try? JSONEncoder().encode(loginPayload) else {
            logger.error("Failed to encode login payload")
            return nil
        }
        request.httpBody = jsonData

        // Create URLSession with optional SSL bypass
        let urlSession: URLSession
        if ignoreSSLErrors {
            let delegate = SSLBypassDelegate()
            urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            urlSession = .shared
        }

        do {
            let (_, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response from login endpoint")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Login failed with status: \(httpResponse.statusCode)")
                return nil
            }

            // Extract JWT token from Set-Cookie header
            if let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie"),
               let tokenRange = setCookie.range(of: "frigate_token="),
               let endRange = setCookie.range(of: ";", range: tokenRange.upperBound..<setCookie.endIndex) {
                let token = String(setCookie[tokenRange.upperBound..<endRange.lowerBound])
                logger.info("Successfully obtained JWT token")
                return token
            } else {
                logger.error("No frigate_token found in Set-Cookie header")
                return nil
            }
        } catch {
            logger.error("Login request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Attempts to fetch Frigate config with a specific auth method
    /// - Parameters:
    ///   - url: The Frigate API config URL
    ///   - authMethod: The authentication method to use
    ///   - host: Frigate hostname
    ///   - port: Frigate port
    ///   - useHTTPS: Whether to use HTTPS
    ///   - username: Username for authentication
    ///   - password: Password for authentication
    ///   - ignoreSSLErrors: Whether to ignore SSL errors
    /// - Returns: Tuple of (data, statusCode)
    private func attemptFetchWithAuth(url: URL, authMethod: FrigateAuthMethod, host: String, port: Int, useHTTPS: Bool, username: String, password: String, ignoreSSLErrors: Bool) async throws -> (Data, Int) {
        // Create request
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.httpMethod = "GET"

        // Add authentication header based on method
        switch authMethod {
        case .none:
            // No authentication header
            logger.debug("Attempting connection with no authentication")

        case .basicAuth:
            // HTTP Basic Auth
            let credentials = "\(username):\(password)"
            if let credentialsData = credentials.data(using: .utf8) {
                let base64Credentials = credentialsData.base64EncodedString()
                request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                logger.debug("Attempting connection with Basic Auth for user: \(username)")
            }

        case .jwt:
            // JWT - need to login first
            guard let jwtToken = await loginToFrigate(
                host: host,
                port: port,
                useHTTPS: useHTTPS,
                username: username,
                password: password,
                ignoreSSLErrors: ignoreSSLErrors
            ) else {
                // Login failed
                throw FrigateError.httpError(statusCode: 401)
            }

            // Use JWT token as Bearer auth
            request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
            logger.debug("Attempting connection with JWT Bearer token")
        }

        // Create URLSession with optional SSL bypass
        let urlSession: URLSession
        if ignoreSSLErrors {
            let delegate = SSLBypassDelegate()
            urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            if authMethod == .none {
                logger.warning("SSL certificate validation disabled")
            }
        } else {
            urlSession = .shared
        }

        // Execute request
        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FrigateError.invalidResponse
        }

        let statusCode = httpResponse.statusCode
        guard statusCode == 200 else {
            logger.debug("HTTP \(statusCode) with \(authMethod.rawValue) auth")
            throw FrigateError.httpError(statusCode: statusCode)
        }

        return (data, statusCode)
    }

    /// Determines the authentication attempt order based on port and context
    /// - Parameter port: The Frigate API port
    /// - Returns: Array of auth methods to try in order
    private func determineAuthAttemptOrder(port: Int) -> [FrigateAuthMethod] {
        switch port {
        case 5000:
            // Port 5000 is Frigate's unauthenticated internal port
            // JWT login endpoint doesn't exist here
            return [.none, .basicAuth]
        case 8971:
            // Port 8971 is Frigate's authenticated port
            // JWT is the native method
            return [.jwt, .none]
        default:
            // Other ports (443, 80, custom) = reverse proxy
            // Try JWT first (Frigate's preferred), then Basic Auth (proxy), then none
            return [.jwt, .basicAuth, .none]
        }
    }

    /// Gets the cached authentication method for a host
    /// - Parameter host: The Frigate hostname
    /// - Returns: Cached auth method or nil
    private func getCachedAuthMethod(for host: String) -> FrigateAuthMethod? {
        let key = "frigate_auth_\(host)"
        guard let rawValue = UserDefaults.standard.string(forKey: key),
              let method = FrigateAuthMethod(rawValue: rawValue) else {
            return nil
        }
        logger.debug("Found cached auth method for \(host): \(method.rawValue)")
        return method
    }

    /// Caches the successful authentication method for a host
    /// - Parameters:
    ///   - method: The auth method that succeeded
    ///   - host: The Frigate hostname
    private func cacheAuthMethod(_ method: FrigateAuthMethod, for host: String) {
        let key = "frigate_auth_\(host)"
        UserDefaults.standard.set(method.rawValue, forKey: key)
        logger.info("Cached auth method for \(host): \(method.rawValue)")
    }

    /// Clears the cached authentication method for a host
    /// - Parameter host: The Frigate hostname
    private func clearCachedAuthMethod(for host: String) {
        let key = "frigate_auth_\(host)"
        UserDefaults.standard.removeObject(forKey: key)
        logger.debug("Cleared cached auth method for \(host)")
    }

    /// Parses Frigate configuration and extracts importable cameras
    private func parseFrigateConfig(_ config: FrigateConfig, go2rtcPublicUrl: String?) -> [FrigateCameraImportable] {
        var cameras: [FrigateCameraImportable] = []

        for (key, frigateCamera) in config.cameras {
            // Skip disabled cameras
            guard frigateCamera.enabled else {
                logger.debug("Skipping disabled camera: \(key)")
                continue
            }

            // Extract camera name (use key if name is not provided)
            let displayName = frigateCamera.name ?? key.replacingOccurrences(of: "_", with: " ").capitalized

            // Parse RTSP streams with smart go2rtc/camera URL extraction
            let (mainStream, subStream) = extractStreams(
                from: frigateCamera.ffmpeg.inputs,
                go2rtcStreams: config.go2rtc?.streams,
                go2rtcPublicUrl: go2rtcPublicUrl
            )

            // Create importable camera
            let importable = FrigateCameraImportable(
                frigateKey: key,
                name: displayName,
                mainStreamUrl: mainStream,
                subStreamUrl: subStream,
                isSelected: true
            )

            cameras.append(importable)

            logger.debug("Parsed camera '\(displayName)' - Main: \(mainStream ?? "none"), Sub: \(subStream ?? "none")")
        }

        return cameras.sorted { $0.name < $1.name }
    }

    /// Checks if a camera with matching RTSP URLs already exists
    /// - Parameters:
    ///   - highResUrl: High resolution RTSP URL to check
    ///   - lowResUrl: Low resolution RTSP URL to check
    ///   - cameraManager: Camera manager to check against
    /// - Returns: True if a camera with matching URLs exists
    private func cameraExists(highResUrl: String, lowResUrl: String, in cameraManager: CameraManager) -> Bool {
        for existingCamera in cameraManager.cameras {
            // Check if both HD and SD URLs match
            // This ensures we're comparing the exact same camera
            if existingCamera.highResUrl == highResUrl && existingCamera.lowResUrl == lowResUrl {
                return true
            }
        }
        return false
    }

    /// Extracts main (HD) and sub (SD) streams from Frigate inputs with smart go2rtc/camera URL resolution
    /// - Parameters:
    ///   - inputs: Array of Frigate input configurations
    ///   - go2rtcStreams: Optional go2rtc stream definitions
    ///   - go2rtcPublicUrl: Optional public go2rtc base URL for restream access
    /// - Returns: Tuple of (mainStreamUrl, subStreamUrl)
    private func extractStreams(from inputs: [FrigateInput], go2rtcStreams: [String: [String]]?, go2rtcPublicUrl: String?) -> (String?, String?) {
        var mainStream: String?
        var subStream: String?

        // Strategy:
        // 1. Find inputs by role (record = HD, detect = SD)
        // 2. For each input, resolve to actual RTSP URL:
        //    a. If user provided go2rtc public URL AND input uses go2rtc proxy -> use public go2rtc URL
        //    b. Else if go2rtc streams available -> extract actual camera URL from go2rtc.streams
        //    c. Else -> use input path directly (direct camera URL)

        for input in inputs {
            let roles = input.roles.map { $0.lowercased() }

            // Resolve the actual URL for this input
            let resolvedUrl = resolveStreamUrl(
                inputPath: input.path,
                go2rtcStreams: go2rtcStreams,
                go2rtcPublicUrl: go2rtcPublicUrl
            )

            // Main stream priority: record > detect
            if mainStream == nil && roles.contains("record") {
                mainStream = resolvedUrl
                continue
            }

            // Sub stream: detect role
            if subStream == nil && roles.contains("detect") {
                subStream = resolvedUrl
                continue
            }
        }

        // Fallback: If we didn't find role-based streams, use first input for both
        if mainStream == nil && !inputs.isEmpty {
            mainStream = resolveStreamUrl(
                inputPath: inputs[0].path,
                go2rtcStreams: go2rtcStreams,
                go2rtcPublicUrl: go2rtcPublicUrl
            )
            subStream = mainStream // Use same stream for both if only one available
        }

        return (mainStream, subStream)
    }

    /// Resolves an input path to an actual RTSP URL with go2rtc support
    /// - Parameters:
    ///   - inputPath: The path from ffmpeg.inputs (may be go2rtc proxy or direct camera URL)
    ///   - go2rtcStreams: Optional go2rtc stream definitions
    ///   - go2rtcPublicUrl: Optional public go2rtc base URL
    /// - Returns: Resolved RTSP URL
    private func resolveStreamUrl(inputPath: String, go2rtcStreams: [String: [String]]?, go2rtcPublicUrl: String?) -> String? {
        // Try to detect if this is a go2rtc stream (supports any IP/hostname on port 8554)
        if let streamName = extractGo2rtcStreamName(from: inputPath, go2rtcStreams: go2rtcStreams) {
            logger.debug("Detected go2rtc stream: \(streamName)")

            // Priority 1: Use public go2rtc URL if provided
            if let publicUrl = go2rtcPublicUrl, !publicUrl.isEmpty {
                let publicStreamUrl = "\(publicUrl)/\(streamName)"
                logger.debug("Using go2rtc public URL: \(publicStreamUrl)")
                return publicStreamUrl
            }

            // Priority 2: Look up actual camera URL in go2rtc.streams
            if let streams = go2rtcStreams, let streamSources = streams[streamName] {
                // Find the first RTSP URL in the sources (ignore ffmpeg: entries)
                for source in streamSources {
                    if source.starts(with: "rtsp://") || source.starts(with: "rtsps://") {
                        logger.debug("Using camera URL from go2rtc.streams: \(source)")
                        return source
                    }
                }
            }

            // Fallback: Use the original URL as-is (may not work remotely)
            logger.warning("go2rtc stream '\(streamName)' not found in config, using original URL: \(inputPath)")
            return inputPath
        }

        // Direct camera URL (already usable)
        return inputPath
    }

    /// Extracts go2rtc stream name from a URL if it appears to be a go2rtc stream
    /// - Parameters:
    ///   - urlString: URL to check (e.g., "rtsp://127.0.0.1:8554/camera1")
    ///   - go2rtcStreams: Optional go2rtc stream definitions for validation
    /// - Returns: Stream name if detected, nil otherwise
    private func extractGo2rtcStreamName(from urlString: String, go2rtcStreams: [String: [String]]?) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        // Check if this looks like a go2rtc stream (port 8554 is go2rtc's default)
        guard url.port == 8554 else { return nil }

        // Extract stream name from path (e.g., "/camera1" → "camera1")
        let streamName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !streamName.isEmpty else { return nil }

        // Verify this stream exists in go2rtc.streams config (prevents false positives)
        if let streams = go2rtcStreams, streams[streamName] != nil {
            return streamName
        }

        // If no go2rtc.streams available, assume it's a go2rtc stream based on port alone
        // This handles cases where go2rtc section exists but streams might be missing
        logger.debug("Assuming '\(streamName)' is go2rtc stream based on port 8554")
        return streamName
    }
}

// MARK: - Authentication Types

enum FrigateAuthMethod: String {
    case none = "none"
    case basicAuth = "basic"
    case jwt = "jwt"
}

// MARK: - Error Types

enum FrigateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Frigate server URL"
        case .invalidResponse:
            return "Invalid response from Frigate server"
        case .httpError(let statusCode):
            switch statusCode {
            case 401:
                return "Authentication required (401). Please check Frigate security settings."
            case 403:
                return "Access forbidden (403). Please check Frigate permissions."
            case 404:
                return "Frigate API not found (404). Please verify the host and port."
            case 500...599:
                return "Frigate server error (\(statusCode)). Please check Frigate logs."
            default:
                return "HTTP error: \(statusCode)"
            }
        case .noData:
            return "No data received from Frigate server"
        }
    }
}

// MARK: - SSL Bypass Delegate

/// URLSession delegate that bypasses SSL certificate validation
/// WARNING: Only use when explicitly requested by user for trusted servers with self-signed certificates
private class SSLBypassDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Only bypass for server trust challenges (SSL certificate validation)
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // For other authentication methods (like HTTP Basic Auth), use default handling
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Accept the server's certificate without validation
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}

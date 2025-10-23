import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigateImporter")

/// Result of importing cameras from Frigate
struct FrigateImportResult {
    let imported: Int
    let skipped: Int
    let overwritten: Int
    let total: Int

    var friendlyMessage: String {
        if total == 0 {
            return "No cameras were selected for import."
        }

        if skipped == 0 && overwritten == 0 {
            if imported == 1 {
                return "Successfully imported 1 camera!"
            } else {
                return "Successfully imported \(imported) cameras!"
            }
        } else if imported == 0 && overwritten == 0 {
            if skipped == 1 {
                return "1 camera was skipped because it already exists in your library."
            } else {
                return "All \(skipped) cameras were skipped because they already exist in your library."
            }
        } else if imported == 0 && skipped == 0 {
            // All overwritten
            if overwritten == 1 {
                return "Successfully overwrote 1 existing camera!"
            } else {
                return "Successfully overwrote \(overwritten) existing cameras!"
            }
        } else {
            // Mixed result
            var parts: [String] = []
            if imported > 0 {
                parts.append("\(imported) new")
            }
            if overwritten > 0 {
                parts.append("\(overwritten) overwritten")
            }
            if skipped > 0 {
                parts.append("\(skipped) skipped")
            }
            return "Import complete: " + parts.joined(separator: ", ")
        }
    }
}

/// Represents a specific Frigate connection scenario (protocol, port, auth)
private struct FrigateScenario {
    let name: String
    let useHTTPS: Bool
    let port: Int
    let authMethod: FrigateAuthMethod
    let requiresCredentials: Bool
}

/// HARDCODED FRIGATE SCENARIOS - TRY IN EXACT ORDER
/// These represent the 6 most common Frigate deployment scenarios
private let FRIGATE_SCENARIOS: [FrigateScenario] = [
    // Scenario #1: Default Local Frigate (most common)
    FrigateScenario(
        name: "#1 Default Local (HTTP:5000, no auth)",
        useHTTPS: false,
        port: 5000,
        authMethod: .none,
        requiresCredentials: false
    ),

    // Scenario #2: Frigate with JWT Authentication Enabled
    FrigateScenario(
        name: "#2 Frigate JWT (HTTP:5000, JWT)",
        useHTTPS: false,
        port: 5000,
        authMethod: .jwt,
        requiresCredentials: true
    ),

    // Scenario #3: HTTPS Reverse Proxy (No Auth)
    FrigateScenario(
        name: "#3 HTTPS Proxy (HTTPS:443, no auth)",
        useHTTPS: true,
        port: 443,
        authMethod: .none,
        requiresCredentials: false
    ),

    // Scenario #4: HTTPS Reverse Proxy + Frigate JWT
    FrigateScenario(
        name: "#4 HTTPS Proxy + JWT (HTTPS:443, JWT)",
        useHTTPS: true,
        port: 443,
        authMethod: .jwt,
        requiresCredentials: true
    ),

    // Scenario #5: HTTPS Reverse Proxy + Basic Auth
    FrigateScenario(
        name: "#5 HTTPS Proxy + Basic Auth (HTTPS:443, Basic)",
        useHTTPS: true,
        port: 443,
        authMethod: .basicAuth,
        requiresCredentials: true
    ),

    // Scenario #6a: HTTP Reverse Proxy (Non-Standard Port) - 8080 + JWT
    FrigateScenario(
        name: "#6 HTTP Proxy 8080 + JWT",
        useHTTPS: false,
        port: 8080,
        authMethod: .jwt,
        requiresCredentials: true
    ),

    // Scenario #6b: HTTP Reverse Proxy 8080 + Basic Auth
    FrigateScenario(
        name: "#6 HTTP Proxy 8080 + Basic Auth",
        useHTTPS: false,
        port: 8080,
        authMethod: .basicAuth,
        requiresCredentials: true
    ),

    // Scenario #6c: HTTP Reverse Proxy 8080 + No Auth
    FrigateScenario(
        name: "#6 HTTP Proxy 8080 (no auth)",
        useHTTPS: false,
        port: 8080,
        authMethod: .none,
        requiresCredentials: false
    ),

    // Scenario #6d: HTTP Reverse Proxy (Home Assistant port 8123) + JWT
    FrigateScenario(
        name: "#6 HTTP Proxy 8123 + JWT",
        useHTTPS: false,
        port: 8123,
        authMethod: .jwt,
        requiresCredentials: true
    ),

    // Scenario #6e: HTTP Reverse Proxy 8123 + Basic Auth
    FrigateScenario(
        name: "#6 HTTP Proxy 8123 + Basic Auth",
        useHTTPS: false,
        port: 8123,
        authMethod: .basicAuth,
        requiresCredentials: true
    ),

    // Scenario #6f: HTTP Reverse Proxy 8123 + No Auth
    FrigateScenario(
        name: "#6 HTTP Proxy 8123 (no auth)",
        useHTTPS: false,
        port: 8123,
        authMethod: .none,
        requiresCredentials: false
    ),
]

@MainActor
class FrigateImporter: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var discoveredCameras: [FrigateCameraImportable] = []

    // MARK: - Public Methods

    /// Connects to Frigate NVR and fetches camera configurations
    /// - Parameters:
    ///   - host: Frigate server hostname or IP address
    ///   - port: Optional explicit port (nil = auto-detect)
    ///   - useHTTPS: Optional explicit protocol (nil = auto-detect)
    ///   - username: Optional username for authentication
    ///   - password: Optional password for authentication
    ///   - go2rtcPublicUrl: Optional public go2rtc base URL (e.g., rtsp://frigate.example.com:8554)
    ///   - ignoreSSLErrors: Whether to ignore SSL certificate validation errors (for self-signed certificates)
    func fetchCameras(host: String, port: Int? = nil, useHTTPS: Bool? = nil, username: String? = nil, password: String? = nil, go2rtcPublicUrl: String? = nil, ignoreSSLErrors: Bool = false) async {
        guard !host.isEmpty else {
            errorMessage = "Please enter a Frigate host address"
            return
        }

        isLoading = true
        errorMessage = nil
        discoveredCameras = []

        let hasCredentials = username != nil && password != nil

        // Determine which scenarios to try
        var scenariosToTry: [FrigateScenario]

        if let explicitPort = port, let explicitHTTPS = useHTTPS {
            // BOTH protocol AND port specified - ONLY try that exact combo
            logger.info("User specified explicit protocol:port (\(explicitHTTPS ? "https" : "http"):\(explicitPort)) - trying only that combination")
            scenariosToTry = createExplicitScenarios(useHTTPS: explicitHTTPS, port: explicitPort, hasCredentials: hasCredentials)

        } else if port != nil || useHTTPS != nil {
            // At least ONE value is explicit - filter hardcoded scenarios
            logger.info("User specified explicit \(useHTTPS != nil ? "protocol" : "port") - filtering scenarios")

            scenariosToTry = FRIGATE_SCENARIOS.filter { scenario in
                let matchesPort = port == nil || scenario.port == port
                let matchesProtocol = useHTTPS == nil || scenario.useHTTPS == useHTTPS
                // If user provided credentials, ONLY try auth scenarios. If no credentials, ONLY try no-auth scenarios.
                let matchesCredentials = scenario.requiresCredentials == hasCredentials
                return matchesPort && matchesProtocol && matchesCredentials
            }

            // If filtered list is empty (e.g., user specified weird port not in hardcoded list),
            // create explicit scenarios for that combo
            if scenariosToTry.isEmpty {
                logger.info("No hardcoded scenarios match, creating explicit scenarios")
                scenariosToTry = createExplicitScenarios(
                    useHTTPS: useHTTPS ?? false,
                    port: port ?? 5000,
                    hasCredentials: hasCredentials
                )
            }

        } else {
            // Neither explicit - try ALL hardcoded scenarios in order
            logger.info("Auto-detecting Frigate configuration - trying all common scenarios")
            scenariosToTry = FRIGATE_SCENARIOS.filter { scenario in
                // If user provided credentials, ONLY try auth scenarios. If no credentials, ONLY try no-auth scenarios.
                scenario.requiresCredentials == hasCredentials
            }
        }

        logger.info("Will try \(scenariosToTry.count) scenarios")

        // Try each scenario in order until one succeeds
        var lastError: Error?

        for scenario in scenariosToTry {
            logger.info("Trying: \(scenario.name)")

            // Build URL for this scenario
            let scheme = scenario.useHTTPS ? "https" : "http"
            guard let url = URL(string: "\(scheme)://\(host):\(scenario.port)/api/config") else {
                logger.error("Invalid URL for scenario: \(scenario.name)")
                continue
            }

            do {
                // Attempt to fetch config with this scenario's auth method
                let (data, _) = try await attemptFetchWithAuth(
                    url: url,
                    authMethod: scenario.authMethod,
                    host: host,
                    port: scenario.port,
                    useHTTPS: scenario.useHTTPS,
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
                    logger.info("✅ SUCCESS with \(scenario.name) - discovered \(cameras.count) cameras")

                    // Cache this successful scenario for next time
                    if hasCredentials {
                        cacheAuthMethod(scenario.authMethod, for: host)
                    }
                }

                isLoading = false
                return

            } catch let error as FrigateError {
                if case .httpError(let code) = error {
                    // 401/403 means auth failed, try next scenario
                    if code == 401 || code == 403 {
                        logger.debug("❌ \(scenario.name) failed with \(code), trying next scenario")
                        lastError = error
                        continue
                    } else if code == 404 {
                        // 404 likely means wrong port or path, try next scenario
                        logger.debug("❌ \(scenario.name) failed with 404 (not found), trying next scenario")
                        lastError = error
                        continue
                    } else if code >= 500 {
                        // Server error, might work with different scenario
                        logger.debug("❌ \(scenario.name) failed with \(code) (server error), trying next scenario")
                        lastError = error
                        continue
                    } else {
                        // Other HTTP errors
                        logger.debug("❌ \(scenario.name) failed with HTTP \(code)")
                        lastError = error
                        continue
                    }
                } else {
                    // Non-HTTP errors (network, invalid response, etc.)
                    logger.debug("❌ \(scenario.name) failed: \(error.localizedDescription)")
                    lastError = error
                    continue
                }
            } catch {
                // Other errors (JSON decode, network timeout, etc.)
                logger.debug("❌ \(scenario.name) failed: \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        // All scenarios failed
        logger.error("All scenarios failed")
        clearCachedAuthMethod(for: host)

        if let error = lastError {
            errorMessage = "Could not connect to Frigate using any common configuration. Last error: \(error.localizedDescription)"
        } else {
            errorMessage = "Could not connect to Frigate server. Please verify the hostname and try specifying the full URL (e.g., https://frigate.example.com:443)"
        }

        isLoading = false
    }

    /// Imports selected cameras into CameraManager
    /// - Parameters:
    ///   - cameras: List of cameras to import (only selected ones will be imported)
    ///   - overwriteDuplicates: If true, overwrites existing cameras with matching URLs; if false, skips them
    /// - Returns: Result containing counts of imported, skipped, and overwritten cameras
    func importCameras(_ cameras: [FrigateCameraImportable], overwriteDuplicates: Bool = false) -> FrigateImportResult {
        let cameraManager = CameraManager.shared
        var importCount = 0
        var skippedCount = 0
        var overwrittenCount = 0
        var totalSelected = 0

        for camera in cameras where camera.isSelected && camera.canImport {
            totalSelected += 1

            // Use main stream for HD, fallback to main for SD if sub doesn't exist
            let hdUrl = camera.mainStreamUrl ?? ""
            let sdUrl = camera.effectiveSubStreamUrl

            // Check if camera already exists by comparing RTSP URLs
            if let existingCamera = findExistingCamera(highResUrl: hdUrl, lowResUrl: sdUrl, in: cameraManager) {
                if overwriteDuplicates {
                    // Overwrite existing camera data
                    logger.info("Overwriting camera '\(camera.name)' - updating existing camera")
                    cameraManager.updateCamera(
                        existingCamera,
                        name: camera.name,
                        highResUrl: hdUrl,
                        lowResUrl: sdUrl,
                        description: "Imported from Frigate NVR",
                        cameraType: .frigate
                    )
                    overwrittenCount += 1
                } else {
                    // Skip existing camera
                    logger.info("Skipping camera '\(camera.name)' - already exists with matching RTSP URLs")
                    skippedCount += 1
                }
                continue
            }

            // Add new camera
            cameraManager.addCamera(
                name: camera.name,
                highResUrl: hdUrl,
                lowResUrl: sdUrl,
                description: "Imported from Frigate NVR",
                cameraType: .frigate
            )
            importCount += 1
        }

        logger.info("Import complete: \(importCount) imported, \(overwrittenCount) overwritten, \(skippedCount) skipped")

        return FrigateImportResult(
            imported: importCount,
            skipped: skippedCount,
            overwritten: overwrittenCount,
            total: totalSelected
        )
    }

    // MARK: - Private Methods

    /// Creates scenarios for an explicit protocol:port combination
    /// - Parameters:
    ///   - useHTTPS: Whether to use HTTPS
    ///   - port: Port number
    ///   - hasCredentials: Whether credentials are available
    /// - Returns: Array of scenarios with all applicable auth methods for that combo
    private func createExplicitScenarios(useHTTPS: Bool, port: Int, hasCredentials: Bool) -> [FrigateScenario] {
        let protocolName = useHTTPS ? "https" : "http"

        if hasCredentials {
            // User provided credentials - ONLY try auth methods (JWT and Basic Auth)
            return [
                FrigateScenario(name: "Explicit \(protocolName):\(port) (JWT)", useHTTPS: useHTTPS, port: port, authMethod: .jwt, requiresCredentials: true),
                FrigateScenario(name: "Explicit \(protocolName):\(port) (Basic Auth)", useHTTPS: useHTTPS, port: port, authMethod: .basicAuth, requiresCredentials: true),
            ]
        } else {
            // No credentials - only try no-auth
            return [
                FrigateScenario(name: "Explicit \(protocolName):\(port) (No Auth)", useHTTPS: useHTTPS, port: port, authMethod: .none, requiresCredentials: false)
            ]
        }
    }

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
                isEnabledInFrigate: frigateCamera.enabled,
                isSelected: frigateCamera.enabled  // Disabled cameras unchecked by default
            )

            cameras.append(importable)

            logger.debug("Parsed camera '\(displayName)' - Enabled: \(frigateCamera.enabled), Main: \(mainStream ?? "none"), Sub: \(subStream ?? "none")")
        }

        return cameras.sorted { $0.name < $1.name }
    }

    /// Finds an existing camera with matching RTSP URLs
    /// - Parameters:
    ///   - highResUrl: High resolution RTSP URL to check
    ///   - lowResUrl: Low resolution RTSP URL to check
    ///   - cameraManager: Camera manager to check against
    /// - Returns: The existing camera if found, nil otherwise
    private func findExistingCamera(highResUrl: String, lowResUrl: String, in cameraManager: CameraManager) -> CameraConfig? {
        for existingCamera in cameraManager.cameras {
            // Check if both HD and SD URLs match
            // This ensures we're comparing the exact same camera
            if existingCamera.highResUrl == highResUrl && existingCamera.lowResUrl == lowResUrl {
                return existingCamera
            }
        }
        return nil
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

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
    func fetchCameras(host: String, port: Int = 5000, useHTTPS: Bool = false, username: String? = nil, password: String? = nil, go2rtcPublicUrl: String? = nil) async {
        guard !host.isEmpty else {
            errorMessage = "Please enter a Frigate host address"
            return
        }

        isLoading = true
        errorMessage = nil
        discoveredCameras = []

        do {
            // Build Frigate API URL
            let scheme = useHTTPS ? "https" : "http"
            guard let url = URL(string: "\(scheme)://\(host):\(port)/api/config") else {
                throw FrigateError.invalidURL
            }

            logger.info("Fetching Frigate config from: \(url.absoluteString)")

            // Create request with timeout
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.httpMethod = "GET"

            // Add HTTP Basic Auth if credentials provided
            if let username = username, let password = password {
                let credentials = "\(username):\(password)"
                if let credentialsData = credentials.data(using: .utf8) {
                    let base64Credentials = credentialsData.base64EncodedString()
                    request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                    logger.debug("Added Basic Auth header for user: \(username)")
                }
            }

            // Execute request
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FrigateError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("HTTP error: \(httpResponse.statusCode)")
                throw FrigateError.httpError(statusCode: httpResponse.statusCode)
            }

            // Parse JSON response
            let decoder = JSONDecoder()
            let frigateConfig = try decoder.decode(FrigateConfig.self, from: data)

            // Parse cameras
            let cameras = parseFrigateConfig(frigateConfig, go2rtcPublicUrl: go2rtcPublicUrl)

            if cameras.isEmpty {
                errorMessage = "No cameras found in Frigate configuration"
            } else {
                discoveredCameras = cameras
                logger.info("Successfully discovered \(cameras.count) cameras from Frigate")
            }

        } catch let error as FrigateError {
            errorMessage = error.localizedDescription
            logger.error("Frigate error: \(error.localizedDescription)")
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            logger.error("Unexpected error: \(error.localizedDescription)")
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

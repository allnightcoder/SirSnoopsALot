import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigateImporter")

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
    func fetchCameras(host: String, port: Int = 5000, useHTTPS: Bool = false) async {
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
            let cameras = parseFrigateConfig(frigateConfig)

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
    func importCameras(_ cameras: [FrigateCameraImportable]) {
        let cameraManager = CameraManager.shared
        var importCount = 0

        for camera in cameras where camera.isSelected && camera.canImport {
            // Use main stream for HD, fallback to main for SD if sub doesn't exist
            let hdUrl = camera.mainStreamUrl ?? ""
            let sdUrl = camera.effectiveSubStreamUrl

            cameraManager.addCamera(
                name: camera.name,
                highResUrl: hdUrl,
                lowResUrl: sdUrl,
                description: "Imported from Frigate NVR"
            )
            importCount += 1
        }

        logger.info("Imported \(importCount) cameras from Frigate")
    }

    // MARK: - Private Methods

    /// Parses Frigate configuration and extracts importable cameras
    private func parseFrigateConfig(_ config: FrigateConfig) -> [FrigateCameraImportable] {
        var cameras: [FrigateCameraImportable] = []

        for (key, frigateCamera) in config.cameras {
            // Skip disabled cameras
            guard frigateCamera.enabled else {
                logger.debug("Skipping disabled camera: \(key)")
                continue
            }

            // Extract camera name (use key if name is not provided)
            let displayName = frigateCamera.name ?? key.replacingOccurrences(of: "_", with: " ").capitalized

            // Parse RTSP streams
            let (mainStream, subStream) = extractStreams(from: frigateCamera.ffmpeg.inputs)

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

    /// Extracts main (HD) and sub (SD) streams from Frigate inputs
    /// - Parameter inputs: Array of Frigate input configurations
    /// - Returns: Tuple of (mainStreamUrl, subStreamUrl)
    private func extractStreams(from inputs: [FrigateInput]) -> (String?, String?) {
        var mainStream: String?
        var subStream: String?

        // Strategy: Find streams based on their roles
        // Main/HD: First stream with "detect" or "record" role
        // Sub/SD: First stream with "clips" role OR second stream

        for input in inputs {
            let roles = input.roles.map { $0.lowercased() }

            // Main stream priority: detect > record
            if mainStream == nil && (roles.contains("detect") || roles.contains("record")) {
                mainStream = input.path
                continue
            }

            // Sub stream: clips role or any other stream
            if subStream == nil && roles.contains("clips") {
                subStream = input.path
                continue
            }
        }

        // Fallback: If we have multiple inputs but didn't find clear roles
        if mainStream == nil && !inputs.isEmpty {
            mainStream = inputs[0].path
        }

        if subStream == nil && inputs.count > 1 {
            subStream = inputs[1].path
        }

        return (mainStream, subStream)
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

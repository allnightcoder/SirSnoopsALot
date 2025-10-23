import Foundation

// MARK: - Frigate API Response Models

/// Root configuration object from Frigate API
struct FrigateConfig: Codable {
    let cameras: [String: FrigateCamera]
}

/// Individual camera configuration from Frigate
struct FrigateCamera: Codable {
    let name: String?
    let enabled: Bool
    let ffmpeg: FrigateFfmpeg

    // Some fields might be missing in the API response
    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case ffmpeg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? true
        self.ffmpeg = try container.decode(FrigateFfmpeg.self, forKey: .ffmpeg)
    }
}

/// FFmpeg configuration containing input streams
struct FrigateFfmpeg: Codable {
    let inputs: [FrigateInput]
}

/// Individual RTSP input stream with its roles
struct FrigateInput: Codable {
    let path: String
    let roles: [String]
}

// MARK: - UI Presentation Models

/// Camera prepared for import into SirSnoopsALot
struct FrigateCameraImportable: Identifiable {
    let id = UUID()
    let frigateKey: String          // Original key from Frigate config
    let name: String                // Display name
    let mainStreamUrl: String?      // HD stream (detect/record role)
    let subStreamUrl: String?       // SD stream (secondary or clips role)
    var isSelected: Bool = true     // User can toggle selection

    /// Can only import if we have at least a main stream
    var canImport: Bool {
        mainStreamUrl != nil && !mainStreamUrl!.isEmpty
    }

    /// Warning message if missing streams
    var warningMessage: String? {
        if mainStreamUrl == nil || mainStreamUrl!.isEmpty {
            return "No RTSP streams found"
        }
        if subStreamUrl == nil || subStreamUrl!.isEmpty {
            return "Only one stream available - will be used for both HD and SD"
        }
        return nil
    }

    /// Get the URL to use for SD (fallback to main if no sub stream)
    var effectiveSubStreamUrl: String {
        if let sub = subStreamUrl, !sub.isEmpty {
            return sub
        }
        return mainStreamUrl ?? ""
    }
}

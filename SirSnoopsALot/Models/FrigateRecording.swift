import Foundation

// MARK: - API Response Models

/// Represents a recording segment from Frigate's /api/{camera}/recordings endpoint
struct FrigateRecording: Codable, Identifiable, Hashable {
    let id: String
    let startTime: Double
    let endTime: Double
    let segmentSize: Double
    let motion: Int
    let objects: Int
    let duration: Double

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case segmentSize = "segment_size"
        case motion
        case objects
        case duration
    }

    var startDate: Date {
        Date(timeIntervalSince1970: startTime)
    }

    var endDate: Date {
        Date(timeIntervalSince1970: endTime)
    }

    var dateInterval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }
}

// MARK: - Timeline Models

/// Represents a segment in the timeline UI
struct TimelineSegment: Identifiable, Hashable {
    let id: String
    let startTime: Date
    let endTime: Date
    let motionScore: Double // 0.0 to 1.0
    let objectScore: Double // 0.0 to 1.0
    let availability: AvailabilityStatus

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var dateInterval: DateInterval {
        DateInterval(start: startTime, end: endTime)
    }
}

enum AvailabilityStatus: String, Codable {
    case available
    case loading
    case unavailable
}

// MARK: - Playback State

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing(currentTime: Date)
    case paused(currentTime: Date)
    case buffering(currentTime: Date)
    case error(String)

    var currentTime: Date? {
        switch self {
        case .playing(let time), .paused(let time), .buffering(let time):
            return time
        default:
            return nil
        }
    }

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
}

// MARK: - Authentication Models

struct FrigateCredentials: Codable {
    let username: String
    let password: String
    let serverURL: URL
}

struct AuthSession: Codable {
    let token: String
    let expiry: Date
    let refreshDate: Date
}

// MARK: - Error Types

enum HistoricalFrigateError: LocalizedError {
    case authentication(String)
    case network(Error)
    case dataParsing(Error)
    case playback(String)
    case timelineUnavailable
    case noRecordingsFound

    var errorDescription: String? {
        switch self {
        case .authentication(let message):
            return "Authentication failed: \(message)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .dataParsing(let error):
            return "Failed to parse data: \(error.localizedDescription)"
        case .playback(let message):
            return "Playback error: \(message)"
        case .timelineUnavailable:
            return "Timeline data unavailable"
        case .noRecordingsFound:
            return "No recordings found for this time range"
        }
    }
}

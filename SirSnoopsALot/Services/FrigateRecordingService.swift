import Foundation
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigateRecordingService")

actor FrigateRecordingService {
    private let authService: FrigateAuthService
    private let serverURL: URL
    private let cameraId: String

    // Simple cache: DateInterval -> [FrigateRecording]
    private var cache: [String: [FrigateRecording]] = [:]

    init(authService: FrigateAuthService, serverURL: URL, cameraId: String) {
        self.authService = authService
        self.serverURL = serverURL
        self.cameraId = cameraId
    }

    // MARK: - Public Methods

    /// Fetch recordings for a specific date range
    func fetchRecordings(range: DateInterval) async throws -> [FrigateRecording] {
        let cacheKey = cacheKeyForRange(range)

        // Check cache first
        if let cached = cache[cacheKey] {
            logger.debug("Returning cached recordings for \(cacheKey)")
            return cached
        }

        // Build URL
        let url = serverURL
            .appendingPathComponent("/api/\(cameraId)/recordings")

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "after", value: String(Int(range.start.timeIntervalSince1970))),
            URLQueryItem(name: "before", value: String(Int(range.end.timeIntervalSince1970)))
        ]

        guard let finalURL = components.url else {
            throw HistoricalFrigateError.network(NSError(domain: "Invalid URL", code: -1))
        }

        // Create authorized request
        var request = URLRequest(url: finalURL)
        request.timeoutInterval = 30.0
        request = try await authService.authorizedRequest(request)

        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HistoricalFrigateError.network(NSError(domain: "Invalid response", code: -1))
        }

        // Handle 401 - auth failed
        if httpResponse.statusCode == 401 {
            throw HistoricalFrigateError.authentication("Authentication expired")
        }

        guard httpResponse.statusCode == 200 else {
            throw HistoricalFrigateError.network(NSError(domain: "HTTP \(httpResponse.statusCode)", code: httpResponse.statusCode))
        }

        // Parse response
        let recordings = try JSONDecoder().decode([FrigateRecording].self, from: data)
        logger.info("Fetched \(recordings.count) recordings for \(self.cameraId)")

        // Cache results
        cache[cacheKey] = recordings

        return recordings
    }

    /// Convert recordings to timeline segments
    func mapToTimelineSegments(_ recordings: [FrigateRecording]) -> [TimelineSegment] {
        return recordings.map { recording in
            // Normalize motion and object scores to 0.0-1.0
            // Assuming max motion/objects per segment is around 100
            let motionScore = min(Double(recording.motion) / 100.0, 1.0)
            let objectScore = min(Double(recording.objects) / 100.0, 1.0)

            return TimelineSegment(
                id: recording.id,
                startTime: recording.startDate,
                endTime: recording.endDate,
                motionScore: motionScore,
                objectScore: objectScore,
                availability: .available
            )
        }
    }

    /// Build VOD URL for a specific time range
    func buildVODURL(start: Date, end: Date) -> URL {
        let startUnix = Int(start.timeIntervalSince1970)
        let endUnix = Int(end.timeIntervalSince1970)

        return serverURL
            .appendingPathComponent("/vod")
            .appendingPathComponent(cameraId)
            .appendingPathComponent("start")
            .appendingPathComponent(String(startUnix))
            .appendingPathComponent("end")
            .appendingPathComponent(String(endUnix))
            .appendingPathComponent("master.m3u8")
    }

    // MARK: - Private Methods

    private func cacheKeyForRange(_ range: DateInterval) -> String {
        "\(Int(range.start.timeIntervalSince1970))-\(Int(range.end.timeIntervalSince1970))"
    }

    func clearCache() {
        cache.removeAll()
    }
}

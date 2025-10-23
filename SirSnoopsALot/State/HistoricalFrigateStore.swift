import Foundation
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "HistoricalFrigateStore")

@MainActor
class HistoricalFrigateStore: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedRange: DateInterval
    @Published var timelineSegments: [TimelineSegment] = []
    @Published var playbackState: PlaybackState = .idle
    @Published var errors: [HistoricalFrigateError] = []
    @Published var isLoadingTimeline = false
    @Published var visibleRange: DateInterval

    // MARK: - Dependencies

    let camera: CameraConfig
    let authService: FrigateAuthService
    let recordingService: FrigateRecordingService
    let playbackController: FrigatePlaybackController

    // MARK: - Private Properties

    private var loadTask: Task<Void, Never>?
    private var playbackTimeObserver: AnyCancellable?

    // MARK: - Initialization

    init(camera: CameraConfig, credentials: FrigateCredentials) {
        self.camera = camera

        // Default to last 24 hours
        let now = Date()
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        let defaultRange = DateInterval(start: dayAgo, end: now)
        self.selectedRange = defaultRange
        self.visibleRange = defaultRange

        // Initialize services
        self.authService = FrigateAuthService()

        // Extract camera ID
        let cameraId = Self.extractFrigateCameraId(from: camera)

        self.recordingService = FrigateRecordingService(
            authService: authService,
            serverURL: credentials.serverURL,
            cameraId: cameraId
        )
        self.playbackController = FrigatePlaybackController(authService: authService)

        // Subscribe to playback controller's state via stream manager
        // This will be set up when playback starts since manager is created on-demand

        // Start authentication
        Task {
            do {
                _ = try await authService.login(credentials: credentials)
                logger.info("Successfully authenticated for camera: \(camera.name)")
            } catch {
                await MainActor.run {
                    self.errors.append(.authentication(error.localizedDescription))
                }
                logger.error("Authentication failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Public Methods

    /// Load timeline for the selected range
    func loadTimeline() {
        // Cancel any existing load
        loadTask?.cancel()

        loadTask = Task { @MainActor in
            isLoadingTimeline = true
            defer { isLoadingTimeline = false }

            do {
                let recordings = try await recordingService.fetchRecordings(range: selectedRange)
                let segments = await recordingService.mapToTimelineSegments(recordings)

                if !Task.isCancelled {
                    timelineSegments = segments
                    logger.info("Loaded \(segments.count) timeline segments")

                    if segments.isEmpty {
                        errors.append(.noRecordingsFound)
                    }
                }
            } catch let error as HistoricalFrigateError {
                if !Task.isCancelled {
                    errors.append(error)
                    logger.error("Failed to load timeline: \(error.localizedDescription)")
                }
            } catch {
                if !Task.isCancelled {
                    errors.append(.network(error))
                    logger.error("Network error loading timeline: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Play video from a specific time
    func play(from time: Date) {
        Task { @MainActor in
            do {
                // Find the segment containing this time
                guard timelineSegments.contains(where: { $0.dateInterval.contains(time) }) else {
                    errors.append(.playback("No recording available for selected time"))
                    return
                }

                // Build VOD URL for a reasonable window around the selected time
                // Use 1 hour window centered on the selected time
                let windowStart = time.addingTimeInterval(-30 * 60)
                let windowEnd = time.addingTimeInterval(30 * 60)
                let vodURL = await recordingService.buildVODURL(start: windowStart, end: windowEnd)

                // Load and play
                playbackState = .loading
                try await playbackController.loadVOD(url: vodURL, startTime: time)

                // Always rewire subscription to the new manager (cancel any previous)
                playbackTimeObserver?.cancel()
                if let manager = playbackController.streamManager {
                    playbackTimeObserver = manager.$state
                        .combineLatest(playbackController.$currentTime.compactMap { $0 })
                        .sink { [weak self] state, time in
                            guard let self = self else { return }

                            switch state {
                            case .preparing, .draining:
                                self.playbackState = .loading
                            case .playing:
                                self.playbackState = .playing(currentTime: time)
                            case .paused:
                                self.playbackState = .paused(currentTime: time)
                            case .idle:
                                self.playbackState = .idle
                            case .failed(let error):
                                self.playbackState = .error(error.localizedDescription)
                            }
                        }
                }

                // Initial state will be set by the publisher above
                logger.info("Started playback from \(time)")
            } catch {
                playbackState = .error(error.localizedDescription)
                errors.append(.playback(error.localizedDescription))
                logger.error("Playback failed: \(error.localizedDescription)")
            }
        }
    }

    /// Pause playback
    func pause() {
        if case .playing = playbackState {
            playbackController.pause()
            // State will update via publisher
        }
    }

    /// Resume playback
    func resume() {
        if case .paused = playbackState {
            playbackController.play()
            // State will update via publisher
        }
    }

    /// Stop playback
    func stop() {
        playbackController.stop()
        // State will update via publisher
    }

    /// Scrub to a specific time
    func scrub(to time: Date) {
        playbackController.seek(to: time)
        if case .playing = playbackState {
            playbackState = .playing(currentTime: time)
        } else if case .paused = playbackState {
            playbackState = .paused(currentTime: time)
        }
    }

    /// Update selected range
    func updateRange(_ range: DateInterval) {
        selectedRange = range
        loadTimeline()
    }

    /// Clear errors
    func clearErrors() {
        errors.removeAll()
    }

    // MARK: - Private Helpers

    private static func extractFrigateCameraId(from camera: CameraConfig) -> String {
        // Extract camera ID from the RTSP URL
        // Example: rtsp://192.168.42.32:8554/1-front_shops -> 1-front_shops
        if let url = URL(string: camera.url),
           let lastPathComponent = url.pathComponents.last,
           lastPathComponent != "/" {
            // Remove any "_record" suffix
            return lastPathComponent.replacingOccurrences(of: "_record", with: "")
        }

        // Fallback to camera name
        return camera.name.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

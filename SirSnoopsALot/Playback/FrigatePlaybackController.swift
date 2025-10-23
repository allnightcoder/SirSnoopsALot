import Foundation
import UIKit
import Combine
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigatePlaybackController")

@MainActor
class FrigatePlaybackController: NSObject, ObservableObject {
    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Date?
    @Published private(set) var error: String?

    private let authService: FrigateAuthService
    private(set) var streamManager: HLSAuthStreamManager?
    private var playbackStartAnchor: Date?
    private var frameObserver: AnyCancellable?
    private var timestampObserver: AnyCancellable?
    private var stateObserver: AnyCancellable?

    init(authService: FrigateAuthService) {
        self.authService = authService
        super.init()
    }

    // MARK: - Public Methods

    /// Load and play a VOD stream for a specific time range
    func loadVOD(url: URL, startTime: Date) async throws {
        logger.info("Loading VOD with FFmpeg: \(url.absoluteString)")

        // Get auth token
        let session = try await authService.refreshIfNeeded()

        // Create stream manager with authentication
        let manager = HLSAuthStreamManager()
        streamManager = manager

        // Observe frames
        frameObserver = manager.$currentFrame
            .compactMap { $0 }
            .sink { [weak self] frame in
                self?.currentFrame = frame
            }

        // Observe timestamps to update currentTime
        timestampObserver = manager.$currentFrameTimestamp
            .compactMap { $0 }
            .sink { [weak self] timestamp in
                guard let self = self, let anchor = self.playbackStartAnchor else { return }
                // The timestamp from FFmpeg is relative to the beginning of the stream
                self.currentTime = anchor.addingTimeInterval(timestamp)
            }

        // Observe state changes
        stateObserver = manager.$state
            .sink { [weak self] state in
                switch state {
                case .preparing:
                    self?.isBuffering = true
                case .playing:
                    self?.isBuffering = false
                    self?.error = nil
                case .paused, .idle:
                    self?.isBuffering = false
                case .draining:
                    self?.isBuffering = false
                case .failed(let err):
                    self?.error = err.localizedDescription
                    self?.isBuffering = false
                }
            }

        playbackStartAnchor = startTime
        currentTime = startTime
        error = nil

        // Start HLS stream with auth header
        manager.startStream(url: url.absoluteString, authToken: session.token)

        logger.info("FFmpeg HLS playback started")
    }

    /// Seek to a specific time
    func seek(to time: Date) {
        // TODO: Implement seek by reloading stream at new time
        // For now, just update the current time marker
        currentTime = time
        logger.info("Seek requested to: \(time)")
    }

    func play() {
        if let manager = streamManager {
            // Resume if manager exists
            manager.resumeStream()
        }
        // Note: For initial playback, loadVOD creates and starts the manager
    }

    func pause() {
        streamManager?.pauseStream()
    }

    func stop() {
        streamManager?.stopStream()
        // Don't nil out streamManager immediately - let it transition to .idle first
        // It will be replaced on next loadVOD call
        currentTime = nil
    }
}

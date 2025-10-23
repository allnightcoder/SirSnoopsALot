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
    private var streamManager: HLSAuthStreamManager?
    private var playbackStartAnchor: Date?
    private var frameObserver: AnyCancellable?

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
        // Note: HLSAuthStreamManager auto-starts playback
        // This method kept for API compatibility
    }

    func pause() {
        streamManager?.stopStream()
    }

    func stop() {
        streamManager?.stopStream()
        streamManager = nil
        currentTime = nil
        currentFrame = nil
    }
}

import Foundation
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "net.virtual-chaos.SirSnoopsALot", category: "FrigatePlaybackController")

@MainActor
class FrigatePlaybackController: NSObject, ObservableObject {
    @Published private(set) var player: AVPlayer
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: Date?
    @Published private(set) var error: String?

    private let authService: FrigateAuthService
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var currentAsset: AVURLAsset?
    private var resourceLoaderDelegate: FrigateResourceLoader?
    private var playbackStartAnchor: Date?

    init(authService: FrigateAuthService) {
        self.authService = authService
        self.player = AVPlayer()
        super.init()
        setupObservers()
    }

    deinit {
        Task { @MainActor in
            if let observer = timeObserver {
                player.removeTimeObserver(observer)
            }
        }
    }

    // MARK: - Public Methods

    /// Load and play a VOD stream for a specific time range
    func loadVOD(url: URL, startTime: Date) async throws {
        logger.info("Loading VOD: \(url.absoluteString)")

        // Create asset with custom resource loader for auth
        let asset = AVURLAsset(url: url)
        let resourceLoader = FrigateResourceLoader(authService: authService)
        asset.resourceLoader.setDelegate(resourceLoader, queue: DispatchQueue.global(qos: .userInitiated))

        // Retain resource loader delegate
        resourceLoaderDelegate = resourceLoader
        currentAsset = asset
        playbackStartAnchor = startTime

        // Create player item
        let playerItem = AVPlayerItem(asset: asset)

        // Replace current item
        await MainActor.run {
            player.replaceCurrentItem(with: playerItem)
            currentTime = startTime
            error = nil
        }

        // Start playback
        player.play()
        logger.info("VOD playback started")
    }

    /// Seek to a specific time
    func seek(to time: Date) {
        guard let currentTime = currentTime else { return }

        let offset = time.timeIntervalSince(currentTime)
        let targetTime = CMTime(seconds: player.currentTime().seconds + offset, preferredTimescale: 600)

        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                Task { @MainActor in
                    self?.currentTime = time
                }
            }
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentAsset = nil
        currentTime = nil
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe playback time
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { @MainActor [weak self] time in
            guard let self = self, let anchor = self.playbackStartAnchor else { return }

            // Update current time based on playback progress from anchor
            self.currentTime = anchor.addingTimeInterval(time.seconds)
        }

        // Observe player status
        statusObserver = player.publisher(for: \.currentItem?.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let status = status else { return }

                switch status {
                case .readyToPlay:
                    self?.isBuffering = false
                case .failed:
                    self?.error = self?.player.currentItem?.error?.localizedDescription
                    self?.isBuffering = false
                case .unknown:
                    self?.isBuffering = true
                @unknown default:
                    break
                }
            }
    }
}

// MARK: - Resource Loader for Authentication

private class FrigateResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let authService: FrigateAuthService

    init(authService: FrigateAuthService) {
        self.authService = authService
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        Task {
            await handleLoadingRequest(loadingRequest)
        }
        return true
    }

    @MainActor
    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) async {
        guard let originalURL = loadingRequest.request.url else {
            loadingRequest.finishLoading(with: NSError(domain: "Invalid URL", code: -1))
            return
        }

        do {
            // Get auth token
            let session = try await authService.refreshIfNeeded()

            // Create authenticated request
            var request = URLRequest(url: originalURL)
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

            // Execute request
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    let error = NSError(domain: "HTTP Error", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"
                    ])
                    loadingRequest.finishLoading(with: error)
                    return
                }

                loadingRequest.response = httpResponse
            }

            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()

        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }
}

import SwiftUI

struct StandaloneCameraView: View {
    let camera: CameraConfig
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var streamManagerObserver: StreamManagerObserver
    
    init(camera: CameraConfig) {
        self.camera = camera
        _streamManagerObserver = StateObject(
            wrappedValue: StreamManagerObserver(
                streamManager: RTSPStreamManager()
            )
        )
        print("StandaloneCameraView - Initialized for camera: \(camera.name)")
    }
    
    var body: some View {
        CameraStreamView(
            camera: camera,
            currentFrame: streamManagerObserver.streamManager.currentFrame
        )
        .navigationTitle(camera.name)
        .onAppear {
            print("StandaloneCameraView - Starting stream for: \(camera.name)")
            streamManagerObserver.streamManager.startStream(url: camera.url)
        }
        .onDisappear {
            print("StandaloneCameraView - Stopping stream for: \(camera.name)")
            streamManagerObserver.streamManager.stopStream()
        }
    }
}

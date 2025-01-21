import SwiftUI

struct StandaloneCameraView: View {
    let camera: CameraConfig
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var streamManagerObserver: StreamManagerObserver
    
    init(camera: CameraConfig) {
        print("StandaloneCameraView - Init started")
        self.camera = camera
        _streamManagerObserver = StateObject(
            wrappedValue: StreamManagerObserver(
                streamManager: RTSPStreamManager()
            )
        )
        print("StandaloneCameraView - Initialized for camera: \(camera.name) with URL: \(camera.url)")
    }
    
    var body: some View {
        CameraStreamView(
            camera: camera,
            currentFrame: streamManagerObserver.streamManager.currentFrame
        )
        .navigationTitle(camera.name)
        .onAppear {
            print("StandaloneCameraView - View appeared for camera: \(camera.name)")
            print("StandaloneCameraView - Attempting to start stream at URL: \(camera.url)")
            streamManagerObserver.streamManager.startStream(url: camera.url)
            print("StandaloneCameraView - Stream start initiated")
        }
        .onDisappear {
            print("StandaloneCameraView - View disappearing for camera: \(camera.name)")
            print("StandaloneCameraView - Initiating stream shutdown")
            streamManagerObserver.streamManager.stopStream()
            print("StandaloneCameraView - Stream stop completed")
        }
    }
}

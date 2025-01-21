import SwiftUI

struct FloatingCameraView: View {
    let camera: CameraConfig
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var streamManagerObserver: StreamManagerObserver
    
    init(camera: CameraConfig) {
        print("FloatingCameraView - Init started")
        self.camera = camera
        _streamManagerObserver = StateObject(
            wrappedValue: StreamManagerObserver(
                streamManager: RTSPStreamManager()
            )
        )
        print("FloatingCameraView - Initialized for camera: \(camera.name) with URL: \(camera.url)")
    }
    
    var body: some View {
        CameraStreamView(
            camera: camera,
            currentFrame: streamManagerObserver.streamManager.currentFrame
        )
        .navigationTitle(camera.name)
        .onAppear {
            print("FloatingCameraView - View appeared for camera: \(camera.name)")
            print("FloatingCameraView - Attempting to start stream at URL: \(camera.url)")
            streamManagerObserver.streamManager.startStream(url: camera.url)
            print("FloatingCameraView - Stream start initiated")
        }
        .onDisappear {
            print("FloatingCameraView - View disappearing for camera: \(camera.name)")
            print("FloatingCameraView - Initiating stream shutdown")
            streamManagerObserver.streamManager.stopStream()
            print("FloatingCameraView - Stream stop completed")
        }
    }
}

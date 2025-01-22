import SwiftUI

struct FloatingCameraView: View {
    let camera: CameraConfig
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var streamManager = RTSPStreamManager()
    
    init(camera: CameraConfig) {
        print("FloatingCameraView - Init started")
        self.camera = camera
        print("FloatingCameraView - Initialized for camera: \(camera.name) with URL: \(camera.url)")
    }
    
    var body: some View {
        CameraStreamView(
            selectedCamera: .constant(camera),
            currentFrame: streamManager.currentFrame
        )
        .navigationTitle(camera.name)
        .onAppear {
            print("FloatingCameraView - View appeared for camera: \(camera.name)")
            print("FloatingCameraView - Attempting to start stream at URL: \(camera.url)")
            streamManager.startStream(url: camera.url)
            print("FloatingCameraView - Stream start initiated")
        }
        .onDisappear {
            print("FloatingCameraView - View disappearing for camera: \(camera.name)")
            print("FloatingCameraView - Initiating stream shutdown")
            streamManager.stopStream()
            print("FloatingCameraView - Stream stop completed")
        }
        .onContinueUserActivity("drag") { activity in
            if let camera = activity.userInfo?["camera"] as? CameraConfig {
                print(camera.url)
            }
        }
    }
}

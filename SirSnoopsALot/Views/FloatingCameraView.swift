import SwiftUI

struct FloatingCameraView: View {
    @State private var camera: CameraConfig?
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var streamManager = RTSPStreamManager()
    
    init() {
        _camera = State(initialValue: nil)
        print("FloatingCameraView - Init started")
    }
    
    var body: some View {
        CameraStreamView(
            selectedCamera: .constant(camera),
            currentFrame: streamManager.currentFrame
        )
        .glassBackgroundEffect(in: .rect)
        .aspectRatio(contentMode: .fit)
        .navigationTitle(camera?.name ?? "")
        .onDisappear {
            print("FloatingCameraView - View disappearing for camera: \(camera?.name ?? "Unknown")")
            streamManager.stopStream()
            print("FloatingCameraView - Stream stop completed")
        }
        .onContinueUserActivity(Activity.floatCamera) { userActivity in
            if let draggedCamera = try? userActivity.typedPayload(CameraConfig.self) {
                print("FloatingCameraView - got dragged cam:", draggedCamera.name)
                camera = draggedCamera
                streamManager.stopStream()
                streamManager.startStream(url: draggedCamera.url)
            }
            else {
                print("FloatingCameraView - bad drag data.")
            }
        }
    }
}

import SwiftUI

struct FloatingCameraView: View {
    @State private var camera: CameraConfig?
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var streamManager = RTSPStreamManager()
    
    init(camera: CameraConfig?) {
        _camera = State(initialValue: camera)
        print("FloatingCameraView - Init started \(camera?.url ?? "Unknown")")
    }
    
    var body: some View {
        CameraStreamView(
            selectedCamera: .constant(camera),
            currentFrame: streamManager.currentFrame,
            onResolutionChange: { updatedCamera in
                camera = updatedCamera
                streamManager.stopStream()
                streamManager.startStream(url: updatedCamera.url)
            }
        )
        .glassBackgroundEffect(in: .rect)
        .aspectRatio(contentMode: .fit)
        .navigationTitle(camera?.name ?? "")
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("FloatingCameraView - Scene phase changed from \(oldPhase) to \(newPhase)")
            
            switch newPhase {
            case .active:
                print("FloatingCameraView - Window becoming active, restarting stream if needed")
                if let validCamera = camera {
                    print("FloatingCameraView - camera found")
                    streamManager.restartStream(url: validCamera.url)
                }
            case .background:
                print("FloatingCameraView - Window entering background, stopping stream")
                streamManager.stopStream()
            default:
                break
            }
        }
        .onDisappear {
            print("FloatingCameraView - View disappearing for camera: \(camera?.name ?? "Unknown")")
            streamManager.stopStream()
            print("FloatingCameraView - Stream stop completed")
        }
        .onAppear() {
            if let validCamera = camera {
                streamManager.startStream(url: validCamera.url)
            }
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

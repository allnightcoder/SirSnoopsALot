//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var selectedCamera: CameraConfig?
    @StateObject private var streamManager = RTSPStreamManager()
    @Environment(\.openWindow) private var openWindow
    @State private var cameraManager = CameraManager.shared
    
    var body: some View {
        NavigationSplitView {
            CameraListView(
                selectedCamera: $selectedCamera
            )
            .navigationDestination(for: CameraConfig.self) { camera in
                CameraStreamView(selectedCamera: $selectedCamera, currentFrame: streamManager.currentFrame)
            }
        } detail: {
            CameraStreamView(selectedCamera: $selectedCamera, currentFrame: streamManager.currentFrame)
        }
        .onAppear {
            selectedCamera = cameraManager.cameras.first
        }
        .onChange(of: selectedCamera) { oldCamera, newCamera in
            print("ContentView - Camera selection changed - Old: \(oldCamera?.name ?? "none"), New: \(newCamera?.name ?? "none")")
            
            if let camera = newCamera {
                switchCameras(newCamera: camera)
            } else {
                print("ContentView - No camera selected, stopping stream")
                streamManager.stopStream()
            }
        }
        .onDisappear {
            print("ContentView - Disappearing, stopping stream")
            streamManager.stopStream()
        }
    }
    
    private func switchCameras(newCamera: CameraConfig) {
        if streamManager.currentStreamURL != newCamera.url {
            print("ContentView - Starting new stream for camera: \(newCamera.name)")
            streamManager.stopStream()
            streamManager.startStream(url: newCamera.url)
        } else {
            print("ContentView - Stream URL unchanged, keeping existing stream")
        }
    }
}

#Preview {
    ContentView()
}

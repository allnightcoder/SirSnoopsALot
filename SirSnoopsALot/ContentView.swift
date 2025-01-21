//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var cameras: [CameraConfig] = []
    @State private var selectedCamera: CameraConfig?
    @StateObject private var streamManager = RTSPStreamManager()
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        NavigationSplitView {
            CameraListView(
                cameras: cameras,
                selectedCamera: $selectedCamera,
                onOpenInNewWindow: { camera in
                    openWindow(value: camera)
                }
            )
        } detail: {
            CameraStreamView(camera: selectedCamera, currentFrame: streamManager.currentFrame)
        }
        .onAppear {
            print("ContentView - Appeared")
            loadCameras()
        }
        .onChange(of: selectedCamera) { oldCamera, newCamera in
            print("ContentView - Camera selection changed - Old: \(oldCamera?.name ?? "none"), New: \(newCamera?.name ?? "none")")
            
            if let camera = newCamera {
                if streamManager.currentStreamURL != camera.url {
                    print("ContentView - Starting new stream for camera: \(camera.name)")
                    streamManager.stopStream()
                    streamManager.startStream(url: camera.url)
                } else {
                    print("ContentView - Stream URL unchanged, keeping existing stream")
                }
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
    
    private func loadCameras() {
        print("ContentView - Loading cameras from UserDefaults")
        if let data = UserDefaults.standard.data(forKey: "cameras") {
            do {
                let decodedCameras = try JSONDecoder().decode([CameraConfig].self, from: data)
                cameras = decodedCameras.sorted(by: { $0.order < $1.order })
                print("ContentView - Successfully loaded \(cameras.count) cameras")
                selectedCamera = cameras.first
                if let first = cameras.first {
                    print("ContentView - Selected first camera: \(first.name)")
                } else {
                    print("ContentView - No cameras available to select")
                }
            } catch {
                print("ContentView - Error decoding cameras: \(error)")
            }
        } else {
            print("ContentView - No camera data found in UserDefaults")
        }
    }
}

#Preview {
    ContentView()
}

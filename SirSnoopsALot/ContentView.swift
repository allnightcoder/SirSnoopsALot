//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var cameras: [CameraConfig] = []
    @State private var selectedCamera: CameraConfig?
    @StateObject private var streamManager = RTSPStreamManager()
    
    var body: some View {
        NavigationSplitView {
            CameraListView(cameras: cameras, selectedCamera: $selectedCamera)
        } detail: {
            CameraStreamView(camera: selectedCamera, currentFrame: streamManager.currentFrame)
        }
        .onAppear {
            loadCameras()
        }
        .onChange(of: selectedCamera) { _, newCamera in
            if let camera = newCamera {
                if streamManager.currentStreamURL != camera.url {
                    streamManager.stopStream()
                    streamManager.startStream(url: camera.url)
                }
            } else {
                streamManager.stopStream()
            }
        }
        .onDisappear {
            streamManager.stopStream()
        }
    }
    
    private func loadCameras() {
        if let data = UserDefaults.standard.data(forKey: "cameras"),
           let decodedCameras = try? JSONDecoder().decode([CameraConfig].self, from: data) {
            cameras = decodedCameras.sorted(by: { $0.order < $1.order })
            selectedCamera = cameras.first
        }
    }
}

#Preview {
    ContentView()
}

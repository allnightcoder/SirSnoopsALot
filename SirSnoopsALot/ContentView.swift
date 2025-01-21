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
            print("ContentView appeared")
            loadCameras()
        }
        .onChange(of: selectedCamera) { oldCamera, newCamera in
            print("Camera selection changed - Old: \(oldCamera?.name ?? "none"), New: \(newCamera?.name ?? "none")")
            
            if let camera = newCamera {
                if streamManager.currentStreamURL != camera.url {
                    print("Starting new stream for camera: \(camera.name)")
                    streamManager.stopStream()
                    streamManager.startStream(url: camera.url)
                } else {
                    print("Stream URL unchanged, keeping existing stream")
                }
            } else {
                print("No camera selected, stopping stream")
                streamManager.stopStream()
            }
        }
        .onDisappear {
            print("ContentView disappearing, stopping stream")
            streamManager.stopStream()
        }
    }
    
    private func loadCameras() {
        print("Loading cameras from UserDefaults")
        if let data = UserDefaults.standard.data(forKey: "cameras") {
            do {
                let decodedCameras = try JSONDecoder().decode([CameraConfig].self, from: data)
                cameras = decodedCameras.sorted(by: { $0.order < $1.order })
                print("Successfully loaded \(cameras.count) cameras")
                selectedCamera = cameras.first
                if let first = cameras.first {
                    print("Selected first camera: \(first.name)")
                } else {
                    print("No cameras available to select")
                }
            } catch {
                print("Error decoding cameras: \(error)")
            }
        } else {
            print("No camera data found in UserDefaults")
        }
    }
}

#Preview {
    ContentView()
}

//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var cameras: [CameraConfig] = []
    @State private var selectedCamera: CameraConfig?
    @StateObject private var streamManager = RTSPStreamManager()
    @State private var isSidebarVisible = true
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(cameras, id: \.order, selection: $selectedCamera) { camera in
                NavigationLink(value: camera) {
                    VStack(alignment: .leading) {
                        Text(camera.name)
                            .font(.headline)
                        Text(camera.url)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Cameras")
            .listStyle(.sidebar)
        } detail: {
            // Main Content
            ZStack {
                if let image = streamManager.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No Stream", systemImage: "video.slash")
                    } description: {
                        Text("Select a camera from the sidebar to begin streaming")
                    }
                }
                
                if let camera = selectedCamera {
                    VStack {
                        Spacer()
                        Text(camera.name)
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(.bottom)
                    }
                }
            }
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

#Preview(windowStyle: .automatic) {
    ContentView()
}

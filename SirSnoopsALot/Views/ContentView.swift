//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedCamera: CameraConfig?
    @StateObject private var streamManager = RTSPStreamManager()
    @State private var cameraManager = CameraManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        NavigationSplitView {
            CameraListView(
                selectedCamera: $selectedCamera
            )
            .navigationDestination(for: CameraConfig.self) { camera in
                CameraStreamView(
                    selectedCamera: $selectedCamera, 
                    currentFrame: streamManager.currentFrame,
                    onResolutionChange: { camera in
                        switchCameras(newCamera: camera)
                    }
                )
            }
        } detail: {
            CameraStreamView(
                selectedCamera: $selectedCamera, 
                currentFrame: streamManager.currentFrame,
                onResolutionChange: { camera in
                    switchCameras(newCamera: camera)
                }
            )
        }
        .onAppear {
            selectedCamera = cameraManager.cameras.first
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("ContentView - Scene phase changed from \(oldPhase) to \(newPhase)")
            
            switch newPhase {
            case .active:
                print("ContentView - Main window becoming active, restarting stream if needed")
                if let camera = selectedCamera {
                    streamManager.startStream(url: camera.url, initialInfo: camera.streamInfo)
                }
            case .background:
                print("ContentView - Main window entering background, closing floating windows")
                streamManager.stopStream()
            default:
                break
            }
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
        .ornament(visibility: .visible, attachmentAnchor: .scene(.topTrailing)) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title2)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    private func switchCameras(newCamera: CameraConfig) {
        if streamManager.currentStreamURL != newCamera.url {
            print("ContentView - Starting new stream for camera: \(newCamera.name)")
            streamManager.stopStream()
            streamManager.startStream(url: newCamera.url, initialInfo: newCamera.streamInfo) { updatedStreamInfo in
                CameraManager.shared.updateStreamInfo(newCamera, isHighRes: newCamera.showHighRes, streamInfo: updatedStreamInfo)
            }
        } else {
            print("ContentView - Stream URL unchanged, keeping existing stream")
        }
    }
}

#Preview {
    ContentView()
}

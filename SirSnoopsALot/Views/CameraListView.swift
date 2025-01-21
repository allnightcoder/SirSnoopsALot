import SwiftUI

struct CameraListView: View {
    let cameras: [CameraConfig]
    @Binding var selectedCamera: CameraConfig?
    
    var body: some View {
        List(cameras, id: \.order, selection: $selectedCamera) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(camera: camera)
            }
        }
        .onChange(of: selectedCamera) { oldValue, newValue in
            print("Camera selection changed - Old: \(String(describing: oldValue?.name)), New: \(String(describing: newValue?.name))")
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
    }
}

struct CameraListItemView: View {
    let camera: CameraConfig
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var windowManager = WindowManager.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(camera.name)
                .font(.headline)
            Text(camera.url)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .contextMenu {
            Button(action: {
                print("Attempting to open camera in new window: \(camera.name)")
                if !windowManager.isCameraOpen(camera.url) {
                    print("Opening new window for camera: \(camera.name)")
                    openWindow(value: camera)
                } else {
                    print("Window already open for camera: \(camera.name)")
                }
            }) {
                Label("Open in New Window", systemImage: "rectangle.on.rectangle")
            }
            .disabled(windowManager.isCameraOpen(camera.url))
            
            Button(action: {
                print("Edit button tapped for camera: \(camera.name)")
                // Edit action
            }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                print("Delete button tapped for camera: \(camera.name)")
                // Delete action
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            print("CameraListItemView appeared for camera: \(camera.name)")
        }
    }
}

#Preview {
    NavigationStack {
        CameraListView(
            cameras: [
                CameraConfig(name: "Test Camera", url: "rtsp://example.com/stream", order: 0)
            ],
            selectedCamera: .constant(nil)
        )
    }
} 
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
                if !windowManager.isCameraOpen(camera.url) {
                    openWindow(value: camera)
                }
            }) {
                Label("Open in New Window", systemImage: "rectangle.on.rectangle")
            }
            .disabled(windowManager.isCameraOpen(camera.url))
            
            Button(action: {
                // Edit action
            }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                // Delete action
            }) {
                Label("Delete", systemImage: "trash")
            }
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
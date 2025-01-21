import SwiftUI

struct CameraListView: View {
    let cameras: [CameraConfig]
    @Binding var selectedCamera: CameraConfig?
    let onOpenInNewWindow: (CameraConfig) -> Void
    
    var body: some View {
        List(cameras, id: \.order, selection: $selectedCamera) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(
                    camera: camera,
                    onOpenInNewWindow: onOpenInNewWindow
                )
            }
        }
        .onChange(of: selectedCamera) { oldValue, newValue in
            print("CameraListView - Camera selection changed - Old: \(String(describing: oldValue?.name)), New: \(String(describing: newValue?.name))")
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
    }
}

struct CameraListItemView: View {
    let camera: CameraConfig
    let onOpenInNewWindow: (CameraConfig) -> Void
    @Environment(\.openWindow) private var openWindow
    
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
                print("CameraListItemView - Attempting to open camera in new window: \(camera.name)")
                onOpenInNewWindow(camera)
            }) {
                Label("Open in New Window", systemImage: "rectangle.on.rectangle")
            }
            
            Button(action: {
                print("CameraListItemView - Edit button tapped for camera: \(camera.name)")
                // Edit action
            }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                print("CameraListItemView - Delete button tapped for camera: \(camera.name)")
                // Delete action
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onAppear {
            print("CameraListItemView - Appeared for camera: \(camera.name)")
        }
    }
}

#Preview {
    NavigationStack {
        CameraListView(
            cameras: [
                CameraConfig(name: "Test Camera", url: "rtsp://example.com/stream", order: 0)
            ],
            selectedCamera: .constant(nil),
            onOpenInNewWindow: { _ in }
        )
    }
} 

import SwiftUICore
import SwiftUI
import UniformTypeIdentifiers

struct CameraListItemView: View {
    let camera: CameraConfig
    let onOpenInNewWindow: (CameraConfig) -> Void
    @Environment(\.openWindow) private var openWindow
    @Binding var cameras: [CameraConfig]
    @State private var showingEditCamera = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(camera.name)
                .font(.headline)
            Text(camera.description)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .draggable(camera)
        .contextMenu {
            Button(action: {
                print("CameraListItemView - Attempting to open camera in new window: \(camera.name)")
                onOpenInNewWindow(camera)
            }) {
                Label("Open in New Window", systemImage: "rectangle.on.rectangle")
            }
            
            Button(action: {
                print("CameraListItemView - Edit button tapped for camera: \(camera.name)")
                showingEditCamera = true
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
        .sheet(isPresented: $showingEditCamera) {
            AddCameraView(cameras: $cameras, editingCamera: camera)
        }
        .onAppear {
            print("CameraListItemView - Appeared for camera: \(camera.name)")
        }
    }
}

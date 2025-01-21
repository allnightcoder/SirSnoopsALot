import SwiftUI

struct CameraListView: View {
    let cameras: [CameraConfig]
    @Binding var selectedCamera: CameraConfig?
    let onOpenInNewWindow: (CameraConfig) -> Void
    @State private var showingAddCamera = false
    @State private var localCameras: [CameraConfig]
    
    init(cameras: [CameraConfig], selectedCamera: Binding<CameraConfig?>, onOpenInNewWindow: @escaping (CameraConfig) -> Void) {
        self.cameras = cameras
        self._selectedCamera = selectedCamera
        self.onOpenInNewWindow = onOpenInNewWindow
        self._localCameras = State(initialValue: cameras)
    }
    
    var body: some View {
        List(localCameras, id: \.order, selection: $selectedCamera) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(
                    camera: camera,
                    onOpenInNewWindow: onOpenInNewWindow,
                    cameras: $localCameras
                )
            }
        }
        .onChange(of: cameras) { _, newCameras in
            print("CameraListView - Cameras array updated with \(newCameras.count) cameras")
            localCameras = newCameras
        }
        .onChange(of: selectedCamera) { oldValue, newValue in
            print("CameraListView - Camera selection changed - Old: \(String(describing: oldValue?.name)), New: \(String(describing: newValue?.name))")
        }
        .onAppear {
            print("CameraListView - Appeared with \(cameras.count) cameras")
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingAddCamera = true
                }) {
                    Label("Add Camera", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCamera) {
            AddCameraView(cameras: $localCameras)
        }
    }
}

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

#Preview {
    NavigationStack {
        CameraListView(
            cameras: [
                CameraConfig(name: "Test Camera", url: "rtsp://example.com/stream", description: "description", order: 0)
            ],
            selectedCamera: .constant(nil),
            onOpenInNewWindow: { _ in }
        )
    }
} 

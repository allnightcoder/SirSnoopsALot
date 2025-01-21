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

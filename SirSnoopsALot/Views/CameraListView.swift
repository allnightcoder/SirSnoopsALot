import SwiftUI

struct CameraListView: View {
    @Binding var selectedCamera: CameraConfig?
    let onOpenInNewWindow: (CameraConfig) -> Void
    @State private var showingAddCamera = false
    @State private var cameraManager = CameraManager.shared
    
    var body: some View {
        List(cameraManager.cameras, id: \.id) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(
                    camera: camera,
                    onOpenInNewWindow: onOpenInNewWindow
                )
            }
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
            AddCameraView()
        }
    }
}

#Preview {
    NavigationStack {
        CameraListView(
            selectedCamera: .constant(nil),
            onOpenInNewWindow: { _ in }
        )
    }
} 

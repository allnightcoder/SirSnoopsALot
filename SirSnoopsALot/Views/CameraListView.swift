import SwiftUI

struct CameraListView: View {
    @Binding var selectedCamera: CameraConfig?
    @State private var showingAddCamera = false
    @State private var cameraManager = CameraManager.shared
    
    var body: some View {
        List(cameraManager.cameras, id: \.id, selection: $selectedCamera) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(
                    camera: camera
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
            selectedCamera: .constant(nil)
        )
    }
} 

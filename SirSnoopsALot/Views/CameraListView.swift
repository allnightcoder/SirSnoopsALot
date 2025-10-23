import SwiftUI

struct CameraListView: View {
    @Binding var selectedCamera: CameraConfig?
    @State private var showingAddCamera = false
    @State private var showingFrigateImport = false
    @StateObject private var cameraManager = CameraManager.shared
    @State private var isSortMode = false
    
    var body: some View {
        List(selection: $selectedCamera) {
            ForEach(cameraManager.cameras, id: \.id) { camera in
                if isSortMode {
                    CameraListItemView(
                        camera: camera,
                        isInSortMode: true
                    )
                } else {
                    NavigationLink(value: camera) {
                        CameraListItemView(
                            camera: camera,
                            isInSortMode: false
                        )
                    }
                }
            }
            .onMove { source, destination in
                cameraManager.moveCamera(from: source, to: destination)
            }
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: {
                        showingAddCamera = true
                    }) {
                        Label("Add Manually", systemImage: "plus.circle")
                    }

                    Button(action: {
                        showingFrigateImport = true
                    }) {
                        Label("Import from Frigate", systemImage: "arrow.down.doc")
                    }
                } label: {
                    Label("Add Camera", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    withAnimation {
                        isSortMode.toggle()
                    }
                }) {
                    Label("Reorder", systemImage: isSortMode ? "checkmark" : "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showingAddCamera) {
            AddCameraView()
        }
        .sheet(isPresented: $showingFrigateImport) {
            ImportFromFrigateView()
        }
        .environment(\.editMode, .constant(isSortMode ? .active : .inactive))
        .onChange(of: isSortMode) { _, newValue in
            if !newValue {
                // Sort mode was disabled, ensure changes are saved
                cameraManager.saveCameras()
            }
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

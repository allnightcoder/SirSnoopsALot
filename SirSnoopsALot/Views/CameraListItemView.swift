import SwiftUICore
import SwiftUI
import UniformTypeIdentifiers

struct CameraListItemView: View {
    let camera: CameraConfig
    let onOpenInNewWindow: (CameraConfig) -> Void
    @Binding var cameras: [CameraConfig]
    @State private var showingEditCamera = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(camera.name)
                .font(.headline)
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
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            Text(camera.description)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .onDrag({
                let userActivity = NSUserActivity(activityType: Activity.floatCamera)
                do {
                    print("CameraListItemView - sending camera")
                    try userActivity.setTypedPayload(camera)
                    userActivity.targetContentIdentifier = Activity.floatCamera
                    let itemProvider = NSItemProvider(object: camera.name as NSString)
                    itemProvider.registerObject(userActivity, visibility: .all)
                    return itemProvider
                } catch {
                    print("Error setting payload: \(error)")
                    return NSItemProvider(object: "Invalid" as NSString)
                }
            },
            preview: {
                Label(camera.name, systemImage: "video")
            })
        // Seems to conflict with onDrag
        // Seems to conflict with onDrag
        // Seems to conflict with onDrag
        // Seems to conflict with onDrag
//        .draggable(camera) {
//            Label(camera.name, systemImage: "video")
//        }
        .sheet(isPresented: $showingEditCamera) {
            AddCameraView(cameras: $cameras, editingCamera: camera)
        }
        .confirmationDialog(
            "Delete Camera",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(camera.name)", role: .destructive) {
                deleteCamera()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this camera? This action cannot be undone.")
        }
        .onAppear {
            print("CameraListItemView - Appeared for camera: \(camera.name)")
        }
    }
    
    private func deleteCamera() {
        if let index = cameras.firstIndex(where: { iteratedCamera in
            iteratedCamera.id == camera.id
        }) {
            print("CameraListItemView - found camera at index \(index) - proceeding to delete \(camera.name)")
            cameras.remove(at: index)
            print("CameraListItemView - reordering cameras before saving")
            // Re-order remaining cameras
            for i in 0..<cameras.count {
                cameras[i].order = i
            }
            // Save to UserDefaults
            do {
                let encodedData = try JSONEncoder().encode(cameras)
                UserDefaults.standard.set(encodedData, forKey: "cameras")
                print("CameraListItemView - Cameras saved after deletion: \(cameras)")
            } catch {
                print("CameraListItemView - Error encoding cameras: \(error)")
            }
        }
    }
}

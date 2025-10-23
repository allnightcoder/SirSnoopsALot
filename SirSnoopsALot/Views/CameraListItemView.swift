import SwiftUI
import UniformTypeIdentifiers

struct CameraListItemView: View {
    let camera: CameraConfig
    let isInSortMode: Bool
    let isInSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var showingEditCamera = false
    @State private var showingDeleteConfirmation = false
    @State private var cameraManager = CameraManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox (only visible in selection mode)
            if isInSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading) {
                Text(camera.name)
                    .font(.headline)
                .contextMenu(menuItems: {
                    if !isInSortMode && !isInSelectionMode {
                        Button(action: {
                            print("CameraListItemView - Attempting to open camera in new window: \(camera.name)")
                            openWindow(id: "floating", value: camera)
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
                })
                Text(camera.description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .opacity(isInSortMode ? 0.8 : 1.0)
        .background(isSelected && isInSelectionMode ? Color.blue.opacity(0.1) : Color.clear)
        .onDrag({
            if isInSortMode || isInSelectionMode { return NSItemProvider() }
            
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
        }, preview: {
            if isInSortMode {
                Label("Reordering", systemImage: "arrow.up.arrow.down")
            } else {
                Label(camera.name, systemImage: "video")
            }
        })
        .sheet(isPresented: $showingEditCamera) {
            AddCameraView(editingCamera: camera)
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
    }
    
    private func deleteCamera() {
        cameraManager.deleteCamera(camera)
    }
}

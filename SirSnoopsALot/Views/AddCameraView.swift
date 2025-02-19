import SwiftUI

struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let editingCamera: CameraConfig?
    @State private var cameraManager = CameraManager.shared
    
    @State private var name: String = ""
    @State private var highResUrl: String = ""
    @State private var lowResUrl: String = ""
    @State private var description: String = ""
    
    init(editingCamera: CameraConfig? = nil) {
        self.editingCamera = editingCamera
        
        if let camera = editingCamera {
            _name = State(initialValue: camera.name)
            _highResUrl = State(initialValue: camera.highResUrl)
            _lowResUrl = State(initialValue: camera.lowResUrl)
            _description = State(initialValue: camera.description)
        }
    }
    
    private func saveCamera() {
        if let editingCamera = editingCamera {
            cameraManager.updateCamera(editingCamera, name: name, highResUrl: highResUrl, lowResUrl: lowResUrl, description: description)
        } else {
            cameraManager.addCamera(name: name, highResUrl: highResUrl, lowResUrl: lowResUrl, description: description)
        }
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Camera Details")) {
                    TextField("Name", text: $name)
                    TextField("High Resolution RTSP URL", text: $highResUrl)
                    TextField("Low Resolution RTSP URL", text: $lowResUrl)
                    TextField("Description", text: $description)
                }
            }
            .navigationTitle(editingCamera != nil ? "Edit Camera" : "Add Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCamera != nil ? "Update" : "Save") {
                        saveCamera()
                    }
                    .disabled(name.isEmpty || highResUrl.isEmpty || lowResUrl.isEmpty)
                }
            }
        }
    }
} 

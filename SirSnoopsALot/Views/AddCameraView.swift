import SwiftUI

struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    let editingCamera: CameraConfig?
    @State private var cameraManager = CameraManager.shared
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var description: String = ""
    
    init(editingCamera: CameraConfig? = nil) {
        self.editingCamera = editingCamera
        
        if let camera = editingCamera {
            _name = State(initialValue: camera.name)
            _url = State(initialValue: camera.url)
            _description = State(initialValue: camera.description)
        }
    }
    
    private func saveCamera() {
        if let editingCamera = editingCamera {
            cameraManager.updateCamera(editingCamera, name: name, url: url, description: description)
        } else {
            cameraManager.addCamera(name: name, url: url, description: description)
        }
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Camera Details")) {
                    TextField("Name", text: $name)
                    TextField("RTSP URL", text: $url)
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
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }
} 

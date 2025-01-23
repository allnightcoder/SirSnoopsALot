import SwiftUI

struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var cameras: [CameraConfig]
    let editingCamera: CameraConfig?
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var description: String = ""
    
    init(cameras: Binding<[CameraConfig]>, editingCamera: CameraConfig? = nil) {
        self._cameras = cameras
        self.editingCamera = editingCamera
        
        // Initialize state with editing camera values if present
        if let camera = editingCamera {
            _name = State(initialValue: camera.name)
            _url = State(initialValue: camera.url)
            _description = State(initialValue: camera.description)
        }
    }
    
    private func getNextOrder() -> Int {
        if let maxOrder = cameras.map({ $0.order }).max() {
            return maxOrder + 1
        }
        return 0
    }
    
    private func saveCamera() {
        if let editingCamera = editingCamera {
            // Update existing camera
            if let index = cameras.firstIndex(where: { $0.order == editingCamera.order }) {
                cameras[index].name = name
                cameras[index].url = url
                cameras[index].description = description
            }
        } else {
            // Add new camera
            let newCamera = CameraConfig(
                id: UUID(),
                name: name,
                url: url,
                description: description,
                order: getNextOrder()
            )
            cameras.append(newCamera)
            cameras.sort(by: { $0.order < $1.order })
        }
        
        // Save to UserDefaults
        do {
            let encodedData = try JSONEncoder().encode(cameras)
            UserDefaults.standard.set(encodedData, forKey: "cameras")
            print("\(editingCamera != nil ? "EditCamera" : "AddCamera")View - Camera saved: \(name)")
        } catch {
            print("\(editingCamera != nil ? "EditCamera" : "AddCamera")View - Error encoding cameras: \(error)")
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

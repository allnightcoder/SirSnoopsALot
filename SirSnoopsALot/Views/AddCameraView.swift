import SwiftUI

struct AddCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var cameras: [CameraConfig]
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var description: String = ""
    
    private func getNextOrder() -> Int {
        if let maxOrder = cameras.map({ $0.order }).max() {
            return maxOrder + 1
        }
        return 0
    }
    
    private func saveCamera() {
        let newCamera = CameraConfig(
            name: name,
            url: url,
            description: description,
            order: getNextOrder()
        )
        
        cameras.append(newCamera)
        cameras.sort(by: { $0.order < $1.order })
        
        // Save to UserDefaults
        do {
            let encodedData = try JSONEncoder().encode(cameras)
            UserDefaults.standard.set(encodedData, forKey: "cameras")
            print("AddCameraView - New camera saved: \(newCamera.name)")
        } catch {
            print("AddCameraView - Error encoding cameras: \(error)")
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
            .navigationTitle("Add Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCamera()
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }
} 
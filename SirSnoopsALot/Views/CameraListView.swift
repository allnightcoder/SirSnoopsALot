import SwiftUI

struct CameraListView: View {
    let cameras: [CameraConfig]
    @Binding var selectedCamera: CameraConfig?
    
    var body: some View {
        List(cameras, id: \.order, selection: $selectedCamera) { camera in
            NavigationLink(value: camera) {
                CameraListItemView(camera: camera)
            }
        }
        .navigationTitle("Cameras")
        .listStyle(.sidebar)
    }
}

struct CameraListItemView: View {
    let camera: CameraConfig
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(camera.name)
                .font(.headline)
            Text(camera.url)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationStack {
        CameraListView(
            cameras: [
                CameraConfig(name: "Test Camera", url: "rtsp://example.com/stream", order: 0)
            ],
            selectedCamera: .constant(nil)
        )
    }
} 
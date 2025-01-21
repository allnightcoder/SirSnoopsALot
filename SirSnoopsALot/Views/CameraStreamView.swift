import SwiftUI

struct CameraStreamView: View {
    let camera: CameraConfig?
    let currentFrame: UIImage?
    
    var body: some View {
        ZStack {
            if let image = currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Stream", systemImage: "video.slash")
                } description: {
                    Text("Select a camera from the sidebar to begin streaming")
                }
            }
            
            if let camera = camera {
                VStack {
                    Spacer()
                    Text(camera.name)
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.bottom)
                }
            }
        }
    }
}

#Preview {
    CameraStreamView(
        camera: CameraConfig(name: "Test Camera", url: "rtsp://example.com/stream", order: 0),
        currentFrame: nil
    )
} 
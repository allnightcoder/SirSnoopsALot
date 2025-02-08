import SwiftUI
import os

struct CameraStreamView: View {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CameraStreamView", category: "UI")
    @Binding var selectedCamera: CameraConfig?
    let currentFrame: UIImage?
    var onResolutionChange: ((CameraConfig) -> Void)?
    let showControls: Bool
    
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
            
            if showControls, let camera = selectedCamera {
                VStack {
                    Spacer()
                    HStack {
                        Text(camera.name)
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        Button(action: {
                            toggleResolution()
                        }) {
                            Text(camera.showHighRes ? "HD" : "SD")
                                .font(.caption.bold())
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .foregroundStyle(camera.showHighRes ? .primary : .secondary)
                                .cornerRadius(8)
                        }
                        .animation(.smooth, value: camera.showHighRes)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .aspectRatio(contentMode: .fit)
        .border(Color.red, width: UserDefaults.standard.bool(forKey: "showCameraFeedBorder") ? 1 : 0)
        .onAppear {
            logger.info("CameraStreamView - appeared - Camera: \(selectedCamera?.name ?? "none")")
            if currentFrame != nil {
                logger.debug("CameraStreamView - Displaying camera frame")
            } else {
                logger.info("CameraStreamView - No camera frame available, showing placeholder")
            }
            if let camera = selectedCamera {
                logger.debug("CameraStreamView - Showing camera overlay for: \(camera.name)")
            }
        }
        .onDisappear {
            logger.info("CameraStreamView - disappeared")
        }
        .dropDestination(for: CameraConfig.self) { items, location in
            if let camera = items.first {
                self.selectedCamera = camera
                return true
            }
            return false
        }
    }
    
    private func toggleResolution() {
        guard var camera = selectedCamera else { return }
        camera.showHighRes.toggle()
        selectedCamera = camera
        CameraManager.shared.updateCameraResolution(camera)
        onResolutionChange?(camera)
    }
}

#Preview {
    CameraStreamView(
        selectedCamera: .constant(CameraConfig(
            id: UUID(),
            name: "Test Camera",
            highResUrl: "rtsp://example.com/stream1",
            lowResUrl: "rtsp://example.com/stream2",
            description: "description",
            order: 0,
            showHighRes: false
        )),
        currentFrame: nil,
        showControls: true
    )
} 

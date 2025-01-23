import Foundation

struct TemplateCameraConfigs {
    static let cameras = [
        CameraConfig(
            id: UUID(),
            name: "Camera 1",
            url: "rtsp://<username>:<password>@<ip>:<port>/<path>",
            description: "Camera 1 description",
            order: 0
        ),
        CameraConfig(
            id: UUID(),
            name: "Camera 2",
            url: "rtsp://<username>:<password>@<ip>:<port>/<path>",
            description: "Camera 2 description",
            order: 1
        )
    ]
} 

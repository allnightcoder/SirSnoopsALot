import Foundation

struct TemplateCameraConfigs {
    static let cameras = [
        CameraConfig(
            id: UUID(),
            name: "Camera 1",
            highResUrl: "rtsp://<username>:<password>@<ip>:<port>/<high-res-path>",
            lowResUrl: "rtsp://<username>:<password>@<ip>:<port>/<low-res-path>",
            description: "Camera 1 description",
            order: 0,
            showHighRes: false
        ),
        CameraConfig(
            id: UUID(),
            name: "Camera 2",
            highResUrl: "rtsp://<username>:<password>@<ip>:<port>/<high-res-path>",
            lowResUrl: "rtsp://<username>:<password>@<ip>:<port>/<low-res-path>",
            description: "Camera 2 description",
            order: 1,
            showHighRes: false
        )
    ]
} 

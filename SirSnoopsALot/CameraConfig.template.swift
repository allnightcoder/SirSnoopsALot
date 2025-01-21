struct TemplateCameraConfigs {
    static let cameras = [
        CameraConfig(
            name: "Camera 1",
            url: "rtsp://<username>:<password>@<ip>:<port>/<path>",
            order: 0
        ),
        CameraConfig(
            name: "Camera 2",
            url: "rtsp://<username>:<password>@<ip>:<port>/<path>",
            order: 1
        )
    ]
} 
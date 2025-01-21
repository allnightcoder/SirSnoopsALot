## Setup

1. Copy `CameraConfig.template.swift` to `CameraConfig.swift`
2. In `CameraConfig.swift`, rename `TemplateCameraConfigs` to `DefaultCameraConfigs`
3. Update the camera configurations in `CameraConfig.swift` with your actual camera credentials
4. Never commit `CameraConfig.swift` to version control

Note: `CameraConfig.swift` is ignored by git to prevent accidentally committing sensitive credentials. 
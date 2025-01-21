//

import SwiftUI

@main
struct SirSnoopsALotApp: App {
    private let enableFFmpegLogging = false

    init() {
        setupDefaultCamerasIfNeeded()
        
        if !enableFFmpegLogging {
            av_log_set_level(AV_LOG_QUIET)
        }
        
        let version = String(cString: av_version_info())
        print("App Init - FFmpeg version: \(version)")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        WindowGroup(for: CameraConfig.self) { $camera in
            if let camera = camera {
                StandaloneCameraView(camera: camera)
            }
        }
    }
    
    private func setupDefaultCamerasIfNeeded() {
        let userDefaults = UserDefaults.standard
        let resetSettings = false // Overwrite userDefaults with CameraConfig.swift settings
        
        // Check if cameras array exists
        if resetSettings || userDefaults.data(forKey: "cameras") == nil {
            if let encodedData = try? JSONEncoder().encode(DefaultCameraConfigs.cameras) {
                userDefaults.set(encodedData, forKey: "cameras")
                print("Default cameras configuration saved to UserDefaults.")
            }
        }
    }
}

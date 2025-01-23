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
        print("SirSnoopsALotApp - FFmpeg version: \(version)")
    }
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        
        WindowGroup(id: "floating") {
            FloatingCameraView()
        }
        .windowStyle(.plain)
        .handlesExternalEvents(matching: [Activity.floatCamera])
    }
    
    private func setupDefaultCamerasIfNeeded() {
        let userDefaults = UserDefaults.standard
        let resetSettings = false  // Changed to false - only set to true temporarily when you want to force reset
        
        // Check if cameras array exists
        let existingData = userDefaults.data(forKey: "cameras")
        if resetSettings {
            print("SirSnoopsALotApp - Resetting camera configuration due to resetSettings flag")
        } else if existingData == nil {
            print("SirSnoopsALotApp - No existing camera configuration found in UserDefaults")
        }
        
        if resetSettings || existingData == nil {
            if let encodedData = try? JSONEncoder().encode(DefaultCameraConfigs.cameras) {
                userDefaults.set(encodedData, forKey: "cameras")
                print("SirSnoopsALotApp - Default cameras configuration saved to UserDefaults.")
            }
            
            userDefaults.set(false, forKey: "showCameraFeedBorder")
        }
    }
}

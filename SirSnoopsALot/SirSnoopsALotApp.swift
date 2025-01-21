//

import SwiftUI

@main
struct SirSnoopsALotApp: App {
    init() {
        setupDefaultCamerasIfNeeded()
        let version = String(cString: av_version_info())
        print("FFmpeg version: \(version)")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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

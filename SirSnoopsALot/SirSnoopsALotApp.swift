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
        
        // Remove old camera URL keys if they exist
        userDefaults.removeObject(forKey: "camera1URL")
        userDefaults.removeObject(forKey: "camera2URL")
        
        // Check if cameras array exists
        if userDefaults.data(forKey: "cameras") == nil {
            if let encodedData = try? JSONEncoder().encode(DefaultCameraConfigs.cameras) {
                userDefaults.set(encodedData, forKey: "cameras")
                print("Default cameras configuration saved to UserDefaults.")
            }
        }
    }
}

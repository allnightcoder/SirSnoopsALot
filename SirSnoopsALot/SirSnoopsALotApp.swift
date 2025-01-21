//

import SwiftUI

@main
struct SirSnoopsALotApp: App {
    let defaultCameras = [
        CameraConfig(
            name: "Camera 1",
            url: "",
            order: 0
        ),
        CameraConfig(
            name: "Camera 2", 
            url: "",
            order: 1
        )
    ]
    
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
            if let encodedData = try? JSONEncoder().encode(defaultCameras) {
                userDefaults.set(encodedData, forKey: "cameras")
                print("Default cameras configuration saved to UserDefaults.")
            }
        }
    }
}

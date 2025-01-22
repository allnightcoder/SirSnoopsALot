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
        
        WindowGroup(id: "other", for: CameraConfig.self) { $camera in
            if let camera = camera {
                FloatingCameraView(camera: camera)
            }
        }
        
        WindowGroup("detail", for: String.self) { $draggedText in
            if let draggedText = draggedText {
                DetailView(draggedString: draggedText)
            } else {
                NopeView()
            }
        }
        .handlesExternalEvents(matching: ["detail"])
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
        }
    }
}

struct DetailView: View {
    let draggedString: String
    
    init(draggedString: String) {
        self.draggedString = draggedString
        print("DetailView starting with \(draggedString)")
    }
    
    var body: some View {
        Text("Detail window with data:\n\(draggedString)")
            .font(.title2)
            .padding()
    }
}

struct NopeView: View {
    
    init() {
        print("NopeView starting")
    }
    
    var body: some View {
        Text("NOPE")
            .font(.title2)
            .padding()
    }
}

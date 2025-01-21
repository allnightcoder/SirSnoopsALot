import SwiftUI

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published private var openCameraWindows: Set<String> = []
    private var streamManagers: [String: RTSPStreamManager] = [:]
    private var streamRefCounts: [String: Int] = [:]
    
    private init() {}
    
    func isCameraOpen(_ url: String) -> Bool {
        openCameraWindows.contains(url)
    }
    
    func getStreamManager(for url: String) -> RTSPStreamManager {
        if let existing = streamManagers[url] {
            print("WindowManager - Reusing existing stream manager for URL: \(url)")
            streamRefCounts[url, default: 0] += 1
            return existing
        }
        print("WindowManager - Creating new stream manager for URL: \(url)")
        let manager = RTSPStreamManager()
        streamManagers[url] = manager
        streamRefCounts[url] = 1
        manager.startStream(url: url)
        return manager
    }
    
    func registerCamera(_ url: String) {
        openCameraWindows.insert(url)
    }
    
    func unregisterCamera(_ url: String) {
        openCameraWindows.remove(url)
        releaseStreamManager(for: url)
    }
    
    func releaseStreamManager(for url: String) {
        if let count = streamRefCounts[url] {
            print("WindowManager - Releasing stream manager for URL: \(url), current ref count: \(count)")
            if count <= 1 {
                if let manager = streamManagers[url] {
                    print("WindowManager - Stopping and removing stream manager for URL: \(url)")
                    manager.stopStream()
                    streamManagers.removeValue(forKey: url)
                    streamRefCounts.removeValue(forKey: url)
                }
            } else {
                streamRefCounts[url] = count - 1
                print("WindowManager - Decremented ref count for URL: \(url), new count: \(count - 1)")
            }
        }
    }
} 
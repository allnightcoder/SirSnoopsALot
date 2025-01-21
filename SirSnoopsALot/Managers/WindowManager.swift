import SwiftUI

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published private var openCameraWindows: Set<String> = []
    private var streamManagers: [String: RTSPStreamManager] = [:]
    private var streamRefCounts: [String: Int] = [:]
    
    private init() {}
    
    func isCameraOpen(_ url: String) -> Bool {
        let isOpen = openCameraWindows.contains(url)
        print("WindowManager - Checking if camera is open for URL: \(url), result: \(isOpen)")
        print("WindowManager - Current open cameras: \(openCameraWindows)")
        return isOpen
    }
    
    func getStreamManager(for url: String) -> RTSPStreamManager {
        print("WindowManager - Attempting to get stream manager for URL: \(url)")
        if let existing = streamManagers[url] {
            print("WindowManager - Reusing existing stream manager for URL: \(url)")
            let newCount = streamRefCounts[url, default: 0] + 1
            streamRefCounts[url] = newCount
            print("WindowManager - Incremented ref count for URL: \(url), new count: \(newCount)")
            return existing
        }
        
        print("WindowManager - Creating new stream manager for URL: \(url)")
        let manager = RTSPStreamManager()
        streamManagers[url] = manager
        streamRefCounts[url] = 1
        print("WindowManager - Initialized new stream manager with ref count 1")
        print("WindowManager - Starting stream for URL: \(url)")
        manager.startStream(url: url)
        return manager
    }
    
    func registerCamera(_ url: String) {
        print("WindowManager - Registering camera with URL: \(url)")
        openCameraWindows.insert(url)
        print("WindowManager - Current open camera count: \(openCameraWindows.count)")
    }
    
    func unregisterCamera(_ url: String) {
        print("WindowManager - Unregistering camera with URL: \(url)")
        openCameraWindows.remove(url)
        print("WindowManager - Current open camera count: \(openCameraWindows.count)")
        releaseStreamManager(for: url)
    }
    
    func releaseStreamManager(for url: String) {
        print("WindowManager - Attempting to release stream manager for URL: \(url)")
        if let count = streamRefCounts[url] {
            print("WindowManager - Current ref count for URL: \(url): \(count)")
            if count <= 1 {
                if let manager = streamManagers[url] {
                    print("WindowManager - Ref count is 1 or less, stopping and removing stream manager")
                    manager.stopStream()
                    streamManagers.removeValue(forKey: url)
                    streamRefCounts.removeValue(forKey: url)
                    print("WindowManager - Stream manager successfully removed")
                } else {
                    print("WindowManager - Warning: Stream manager not found for URL: \(url)")
                }
            } else {
                let newCount = count - 1
                streamRefCounts[url] = newCount
                print("WindowManager - Decremented ref count for URL: \(url), new count: \(newCount)")
            }
        } else {
            print("WindowManager - Warning: No ref count found for URL: \(url)")
        }
    }
} 
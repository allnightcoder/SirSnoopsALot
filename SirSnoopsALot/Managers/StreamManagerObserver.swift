import SwiftUI

class StreamManagerObserver: ObservableObject {
    @Published var streamManager: RTSPStreamManager
    
    init(streamManager: RTSPStreamManager) {
        self.streamManager = streamManager
    }
} 
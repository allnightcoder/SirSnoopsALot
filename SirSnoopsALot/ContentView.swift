//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @State private var camera1URL = UserDefaults.standard.string(forKey: "camera2URL") ?? "Not set"
    @StateObject private var streamManager = RTSPStreamManager()
    
    var body: some View {
        VStack {
            if let image = streamManager.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No stream available")
                    .foregroundColor(.gray)
            }
            
            Text("Camera URL: \(camera1URL)")
                .font(.caption)
                .padding()
        }
        .padding()
        .onAppear {
            streamManager.startStream(url: camera1URL)
        }
        .onDisappear {
            streamManager.stopStream()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}

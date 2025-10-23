import Foundation
import SwiftUI

final class CameraManager: ObservableObject {
    static let shared = CameraManager()
    
    @Published var cameras: [CameraConfig] = []
    private var hasLoadedInitialData = false
    
    private init() {
        loadCameras()
    }
    
    // MARK: - Public Methods
    
    func addCamera(name: String, highResUrl: String, lowResUrl: String, description: String, cameraType: CameraType? = nil) {
        let newCamera = CameraConfig(
            id: UUID(),
            name: name,
            highResUrl: highResUrl,
            lowResUrl: lowResUrl,
            description: description,
            order: getNextOrder(),
            showHighRes: false,
            cameraType: cameraType
        )
        cameras.append(newCamera)
        cameras.sort(by: { $0.order < $1.order })
        saveCameras()
    }
    
    func updateCamera(_ camera: CameraConfig, name: String, highResUrl: String, lowResUrl: String, description: String, cameraType: CameraType? = nil) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index].name = name
            cameras[index].highResUrl = highResUrl
            cameras[index].lowResUrl = lowResUrl
            cameras[index].description = description
            cameras[index].cameraType = cameraType
            saveCameras()
        }
    }
    
    func updateStreamInfo(_ camera: CameraConfig, isHighRes: Bool, streamInfo: RTSPInfo?) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            let oldStreamInfo = cameras[index].streamInfo
            let newStreamInfo = streamInfo
            
            // Only proceed if the stream info has actually changed
            if oldStreamInfo != newStreamInfo {
                print("CameraManager - Updating stream info for camera \(camera.name)")
                
                // Print old stream info
                if let old = oldStreamInfo {
                    print("CameraManager - Old stream info:")
                    print(old.debugDescription)
                } else {
                    print("CameraManager - Old stream info: nil")
                }
                
                // Print new stream info
                if let new = newStreamInfo {
                    print("CameraManager - New stream info:")
                    print(new.debugDescription)
                } else {
                    print("CameraManager - New stream info: nil")
                }
                
                cameras[index].streamInfo = newStreamInfo
                saveCameras()
            } else {
                print("CameraManager - Stream info unchanged for camera \(camera.name)")
            }
        }
    }
    
    func deleteCamera(_ camera: CameraConfig) {
        cameras.removeAll(where: { $0.id == camera.id })
        reorderCameras()
        saveCameras()
    }

    func deleteCameras(_ cameraIds: Set<UUID>) {
        cameras.removeAll(where: { cameraIds.contains($0.id) })
        reorderCameras()
        saveCameras()
    }

    func saveCameras() {
        do {
            let encodedData = try JSONEncoder().encode(cameras)
            UserDefaults.standard.set(encodedData, forKey: "cameras")
            print("CameraManager - Successfully saved \(cameras.count) cameras")
        } catch {
            print("CameraManager - Error encoding cameras: \(error)")
        }
    }
    
    func moveCamera(from source: IndexSet, to destination: Int) {
        cameras.move(fromOffsets: source, toOffset: destination)
        reorderCameras()
        saveCameras()
    }
    
    func updateCameraResolution(_ camera: CameraConfig) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index].showHighRes = camera.showHighRes
            saveCameras()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCameras() {
        print("CameraManager - Loading cameras from UserDefaults")
        
        if let data = UserDefaults.standard.data(forKey: "cameras") {
            do {
                let decodedCameras = try JSONDecoder().decode([CameraConfig].self, from: data)
                cameras = decodedCameras.sorted(by: { $0.order < $1.order })
                print("CameraManager - Successfully loaded \(cameras.count) cameras")
            } catch {
                print("CameraManager - Error decoding cameras: \(error)")
            }
        } else {
            print("CameraManager - No camera data found in UserDefaults")
        }
    }
    
    private func getNextOrder() -> Int {
        (cameras.map(\.order).max() ?? -1) + 1
    }
    
    private func reorderCameras() {
        for (index, _) in cameras.enumerated() {
            cameras[index].order = index
        }
    }
} 

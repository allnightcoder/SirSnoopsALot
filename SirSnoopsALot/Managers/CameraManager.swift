import Foundation
import SwiftUI

@Observable
final class CameraManager {
    static let shared = CameraManager()
    
    var cameras: [CameraConfig] = []
    private var hasLoadedInitialData = false
    
    private init() {
        loadCameras()
    }
    
    // MARK: - Public Methods
    
    func addCamera(name: String, url: String, description: String) {
        let newCamera = CameraConfig(
            id: UUID(),
            name: name,
            url: url,
            description: description,
            order: getNextOrder()
        )
        cameras.append(newCamera)
        cameras.sort(by: { $0.order < $1.order })
        saveCameras()
    }
    
    func updateCamera(_ camera: CameraConfig, name: String, url: String, description: String) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index].name = name
            cameras[index].url = url
            cameras[index].description = description
            saveCameras()
        }
    }
    
    func deleteCamera(_ camera: CameraConfig) {
        cameras.removeAll(where: { $0.id == camera.id })
        reorderCameras()
        saveCameras()
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
    
    private func saveCameras() {
        do {
            let encodedData = try JSONEncoder().encode(cameras)
            UserDefaults.standard.set(encodedData, forKey: "cameras")
            print("CameraManager - Successfully saved \(cameras.count) cameras")
        } catch {
            print("CameraManager - Error encoding cameras: \(error)")
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
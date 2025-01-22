import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct CameraConfig: Codable, Transferable, Hashable {
    var name: String
    var url: String
    var description: String
    var order: Int
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .camera)
    }
}

struct Activity {
    /// This is the activityType for drag-drop
    static let floatCamera = "net.virtual-chaos.sirsnoopsalot.floatCamera"
}

extension UTType {
    static var camera: UTType {
        UTType(exportedAs: "net.virtual-chaos.sirsnoopsalot.camera")
    }
}

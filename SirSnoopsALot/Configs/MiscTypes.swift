import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct CameraConfig: Codable, Transferable, Hashable {
    var id: UUID
    var name: String
    var highResUrl: String
    var lowResUrl: String
    var description: String
    var order: Int
    var showHighRes: Bool
    
    var url: String {
        showHighRes ? highResUrl : lowResUrl
    }
    
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

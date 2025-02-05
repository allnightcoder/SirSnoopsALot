import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Holds pre-probed (cached) RTSP metadata to speed up future stream openings.
class RTSPInfo: Codable, Hashable, CustomDebugStringConvertible {
    var codecID: Int32
    var width: Int
    var height: Int

    /// Extra data for the codec (e.g. H.264 SPS/PPS).
    var extraData: Data?
    
    init(codecID: Int32, width: Int, height: Int, extraData: Data?) {
        self.codecID = codecID
        self.width = width
        self.height = height
        self.extraData = extraData
    }
    
    // MARK: - Hashable & Equatable
    static func == (lhs: RTSPInfo, rhs: RTSPInfo) -> Bool {
        return lhs.codecID == rhs.codecID
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.extraData == rhs.extraData
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(codecID)
        hasher.combine(width)
        hasher.combine(height)
        // Not strictly necessary to hash extradata, but you could.
    }
    
    // MARK: - Debug Description
    var debugDescription: String {
        """
        RTSPInfo {
            codecID: \(codecID)
            resolution: \(width)x\(height)
            extraData: \(extraData?.count ?? 0) bytes
        }
        """
    }
}

struct CameraConfig: Codable, Transferable, Hashable {
    var id: UUID
    var name: String
    var highResUrl: String
    var lowResUrl: String
    var description: String
    var order: Int
    var showHighRes: Bool
    
    // This property selects which URL is in use.
    var url: String {
        showHighRes ? highResUrl : lowResUrl
    }
    
    // Caches the previously probed info for faster re-open. If not nil,
    // your RTSP manager can skip or reduce certain steps.
    var streamInfo: RTSPInfo?
    
    // MARK: - Transferable
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

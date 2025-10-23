import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Represents the source/type of a camera
enum CameraType: String, Codable, CaseIterable {
    case frigate = "frigate"

    var displayName: String {
        switch self {
        case .frigate:
            return "Frigate"
        }
    }
}

/// Holds pre-probed (cached) RTSP metadata to speed up future stream openings.
class RTSPInfo: Codable, Hashable, CustomDebugStringConvertible {
    var codecID: Int32
    var width: Int
    var height: Int
    var format: Int
    var bitRate: Int64
    var videoStreamIndex: Int32

    /// Extra data for the codec (e.g. H.264 SPS/PPS).
    var extraData: Data?
    
    init(codecID: Int32, width: Int, height: Int, format: Int, bitRate: Int64, videoStreamIndex: Int32, extraData: Data?) {
        self.codecID = codecID
        self.width = width
        self.height = height
        self.format = format
        self.bitRate = bitRate
        self.videoStreamIndex = videoStreamIndex
        self.extraData = extraData
    }
    
    // MARK: - Hashable & Equatable
    static func == (lhs: RTSPInfo, rhs: RTSPInfo) -> Bool {
        return lhs.codecID == rhs.codecID
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.format == rhs.format
            && lhs.bitRate == rhs.bitRate
            && lhs.videoStreamIndex == rhs.videoStreamIndex
            && lhs.extraData == rhs.extraData
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(codecID)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(format)
        hasher.combine(bitRate)
        // Not strictly necessary to hash extradata, but you could.
    }
    
    // MARK: - Debug Description
    var debugDescription: String {
        """
        RTSPInfo {
            codecID: \(codecID)
            resolution: \(width)x\(height)
            format: \(format)
            bitRate: \(bitRate)
            videoStreamIndex: \(videoStreamIndex)
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
    var cameraType: CameraType?
    var highResStreamInfo: RTSPInfo?
    var lowResStreamInfo: RTSPInfo?
    
    var url: String {
        showHighRes ? highResUrl : lowResUrl
    }
    
    var streamInfo: RTSPInfo? {
        get {
            showHighRes ? highResStreamInfo : lowResStreamInfo
        }
        set {
            if showHighRes {
                highResStreamInfo = newValue
            } else {
                lowResStreamInfo = newValue
            }
        }
    }
    
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

import Foundation
import UIKit
import CoreGraphics

// MARK: - FFmpeg Imports & Constants
let AVERROR_EOF: Int32 = -541478725  // -MKTAG('E','O','F',' ')
func AVERROR(_ errno: Int32) -> Int32 {
    return -errno
}

// Helper function since av_err2str is a macro in C
func av_err2str(_ errnum: Int32) -> String {
    var buffer = [Int8](repeating: 0, count: 64)
    av_strerror(errnum, &buffer, 64)
    return String(cString: buffer)
}

// Example transport enum for RTSP
enum RTSPTransport: String {
    case tcp = "tcp"
    case udp = "udp"
    case udpMulticast = "udp_multicast"
}

/// Manages an RTSP stream using FFmpeg, with a fallback mechanism to skip or reduce analysis
/// if we have cached info, but revert to a full parse if that fails.
class RTSPStreamManager: ObservableObject {
    @Published var currentFrame: UIImage?
    
    /// Current active RTSP URL (if streaming). Set when stream is started.
    private(set) var currentStreamURL: String?
    
    // Internal FFmpeg contexts & state
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    
    private var isRunning = false
    
    // Called when we discover or reaffirm new RTSP info
    private var onStreamInfoUpdate: ((RTSPInfo?) -> Void)?
    
    // If you want to trigger fallback after some number of early decode failures:
    private var decodeFailureCount = 0
    private let maxEarlyFailuresBeforeFallback = 5
    
    // Used for fallback logic
    private var fallbackAllowed = true
    
    // Cache of previously known RTSP info. If non-nil, we attempt an "aggressive" approach.
    private var cachedRTSPInfo: RTSPInfo?
    
    // MARK: - Dictionaries
    
    /// Generic / default dictionary for normal open.
    private func defaultDictionary(transport: RTSPTransport, useHWAccel: Bool) -> OpaquePointer? {
        var dict: OpaquePointer? = nil
        
        av_dict_set(&dict, "rtsp_transport", transport.rawValue, 0)
        
        // Possibly set a read timeout in microseconds, etc.
        av_dict_set(&dict, "stimeout", "3000000", 0) // 3 seconds
        av_dict_set(&dict, "max_delay", "500000", 0) // 0.5 seconds
        
        // Optional hardware accel placeholder (videotoolbox or others).
        if useHWAccel {
            // This alone typically isn't enough; real HWaccel requires additional setup.
            av_dict_set(&dict, "hwaccel", "videotoolbox", 0)
        }
        return dict
    }
    
    /// Fast-start dictionary with minimal analysis.
    private func fastStartupDictionary(transport: RTSPTransport, useHWAccel: Bool) -> OpaquePointer? {
        var dict: OpaquePointer? = nil
        
        av_dict_set(&dict, "rtsp_transport", transport.rawValue, 0)
        
        // Smaller analyze durations & buffers
        av_dict_set(&dict, "analyzeduration", "100000", 0) // 0.1s
        av_dict_set(&dict, "probesize", "100000", 0)       // 100 KB
        av_dict_set(&dict, "fflags", "nobuffer", 0)
        av_dict_set(&dict, "flags", "low_delay", 0)
        
        // Possibly also reduce "stimeout" or "max_delay"
        av_dict_set(&dict, "stimeout", "1000000", 0) // 1 second
        av_dict_set(&dict, "max_delay", "250000", 0) // 0.25 seconds
        
        // Optional hardware accel placeholder
        if useHWAccel {
            av_dict_set(&dict, "hwaccel", "videotoolbox", 0)
        }
        return dict
    }
    
    // MARK: - Public API
    
    /**
     Start streaming from an RTSP `url`, optionally using cached `RTSPInfo`.
     
     - parameter url: The RTSP URL to open.
     - parameter initialInfo: Previously cached `RTSPInfo` if known (used for an aggressive skip).
     - parameter transport: .tcp, .udp, or .udpMulticast
     - parameter useHWAccel: Whether to attempt hardware acceleration
     - parameter onStreamInfoUpdate: Callback triggered when new or updated RTSPInfo is discovered
     */
    func startStream(
        url: String,
        initialInfo: RTSPInfo? = nil,
        transport: RTSPTransport = .tcp,
        useHWAccel: Bool = false,
        onStreamInfoUpdate: ((RTSPInfo?) -> Void)? = nil
    ) {
        self.currentStreamURL = url
        self.cachedRTSPInfo = initialInfo
        self.onStreamInfoUpdate = onStreamInfoUpdate
        self.fallbackAllowed = true
        
        print("RTSPStreamManager - startStream: \(url), haveCached=\(initialInfo != nil)")
        
        openStream(url: url, transport: transport, useHWAccel: useHWAccel)
    }
    
    /// Stop the current stream.
    func stopStream() {
        guard currentStreamURL != nil else {
            print("RTSPStreamManager - Stop requested but no active stream")
            return
        }
        
        print("RTSPStreamManager - Stopping stream: \(currentStreamURL ?? "None")")
        isRunning = false
        
        DispatchQueue.main.async {
            self.currentStreamURL = nil
        }
        
        // Wait briefly to ensure the decoding loop has stopped
        Thread.sleep(forTimeInterval: 0.2)
        
        cleanupResources()
        
        print("RTSPStreamManager - ✅ Stream stopped and resources cleaned up")
    }
    
    deinit {
        stopStream()
    }
    
    // MARK: - Internal: openStream
    
    private func openStream(url: String, transport: RTSPTransport, useHWAccel: Bool) {
        guard !url.contains("Not set") else { return }
        
        if let info = cachedRTSPInfo {
            // We have prior info => skip find_stream_info if possible
            print("RTSPStreamManager - Using AGGRESSIVE open with cached info: \(info.debugDescription)")
            openStreamAggressive(url: url, transport: transport, useHWAccel: useHWAccel, info: info)
        } else {
            // No cached info => do full approach
            print("RTSPStreamManager - No cached info, calling openStreamDefault")
            openStreamDefault(url: url, transport: transport, useHWAccel: useHWAccel)
        }
    }
    
    // MARK: - 1) Full / Default open with avformat_find_stream_info
    
    private func openStreamDefault(url: String, transport: RTSPTransport, useHWAccel: Bool) {
        var options: OpaquePointer? = defaultDictionary(transport: transport, useHWAccel: useHWAccel)
        
        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        let resOpen = avformat_open_input(&formatCtx, url, nil, &options)
        av_dict_free(&options)
        
        guard resOpen >= 0, let validCtx = formatCtx else {
            print("RTSPStreamManager - ❌ openStreamDefault failed open_input")
            return
        }
        self.formatContext = validCtx
        
        // Full analysis
        if avformat_find_stream_info(validCtx, nil) < 0 {
            print("RTSPStreamManager - ❌ openStreamDefault: avformat_find_stream_info failed")
            cleanupResources()
            return
        }
        print("RTSPStreamManager - ✅ openStreamDefault: found stream info")
        
        // Find the video stream
        var videoStreamIndex: Int32 = -1
        for i in 0..<Int(validCtx.pointee.nb_streams) {
            let stream = validCtx.pointee.streams[i]
            if stream?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int32(i)
                break
            }
        }
        guard videoStreamIndex != -1 else {
            print("RTSPStreamManager - No video stream found in default open")
            return
        }
        
        guard let codecParams = validCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar else {
            print("RTSPStreamManager - Failed to get codec parameters in default open")
            return
        }
        
        guard let codec = avcodec_find_decoder(codecParams.pointee.codec_id) else {
            print("RTSPStreamManager - Failed to find decoder in default open")
            return
        }
        
        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("RTSPStreamManager - Failed to alloc codec context in default open")
            return
        }
        
        guard avcodec_parameters_to_context(codecCtx, codecParams) >= 0 else {
            print("RTSPStreamManager - Failed avcodec_parameters_to_context in default open")
            return
        }
        
        let resCodecOpen = avcodec_open2(codecCtx, codec, nil)
        guard resCodecOpen >= 0 else {
            print("RTSPStreamManager - Failed avcodec_open2 in default open: \(av_err2str(resCodecOpen))")
            return
        }
        
        // Allocate frame/packet
        frame = av_frame_alloc()
        packet = av_packet_alloc()
        
        // Cache discovered stream info for next time
        let discoveredCodecID = Int32(codecParams.pointee.codec_id.rawValue)
        let discoveredWidth = Int(codecParams.pointee.width)
        let discoveredHeight = Int(codecParams.pointee.height)
        
        // Extract extradata if present
        var extradataData: Data? = nil
        if codecParams.pointee.extradata_size > 0,
           let ptr = codecParams.pointee.extradata {
            let size = Int(codecParams.pointee.extradata_size)
            extradataData = Data(bytes: ptr, count: size)
        }
        
        let newInfo = RTSPInfo(codecID: discoveredCodecID,
                               width: discoveredWidth,
                               height: discoveredHeight,
                               extraData: extradataData)
        
        // Notify the caller that we've discovered new info
        DispatchQueue.main.async {
            self.onStreamInfoUpdate?(newInfo)
        }
        
        print("RTSPStreamManager - ✅ openStreamDefault complete. Starting decode loop.")
        decodeFailureCount = 0
        isRunning = true
        startDecodingLoop(url: url, transport: transport, useHWAccel: useHWAccel)
    }
    
    // MARK: - 2) Aggressive open that skips find_stream_info
    
    private func openStreamAggressive(url: String,
                                      transport: RTSPTransport,
                                      useHWAccel: Bool,
                                      info: RTSPInfo) {
        print("RTSPStreamManager - openStreamAggressive: skipping avformat_find_stream_info")
        
        // Minimal dictionary
        var options: OpaquePointer? = fastStartupDictionary(transport: transport, useHWAccel: useHWAccel)
        
        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        let openRes = avformat_open_input(&formatCtx, url, nil, &options)
        av_dict_free(&options)
        
        guard openRes >= 0, let validFormatCtx = formatCtx else {
            print("RTSPStreamManager - ❌ Aggressive open: avformat_open_input failed")
            fallbackIfNeeded(url: url, transport: transport, useHWAccel: useHWAccel, whereFailed: "aggressive_open_input")
            return
        }
        self.formatContext = validFormatCtx
        
        // Skip avformat_find_stream_info entirely
        // Some RTSP servers might automatically parse a single stream index
        guard validFormatCtx.pointee.nb_streams > 0 else {
            print("RTSPStreamManager - No streams found in aggressive open")
            fallbackIfNeeded(url: url, transport: transport, useHWAccel: useHWAccel, whereFailed: "no_streams_aggressive")
            return
        }
        
        // We'll assume stream index 0 for video, or pick first that is video
        let stream = validFormatCtx.pointee.streams[0]
        // If you need to verify it's video, do so. We'll keep it simple:
        
        // Create codec context from the cached info
        let wantedCodecID = AVCodecID(UInt32(info.codecID))
        guard let codec = avcodec_find_decoder(wantedCodecID) else {
            print("RTSPStreamManager - ❌ Aggressive open: failed avcodec_find_decoder for \(info.codecID)")
            fallbackIfNeeded(url: url, transport: transport, useHWAccel: useHWAccel, whereFailed: "find_decoder_aggressive")
            return
        }
        
        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("RTSPStreamManager - ❌ Aggressive open: avcodec_alloc_context3 failed")
            return
        }
        
        // Manually set known parameters
        codecCtx.pointee.codec_id = wantedCodecID
        codecCtx.pointee.width    = Int32(info.width)
        codecCtx.pointee.height   = Int32(info.height)
        
        // If we have extradata, feed it in
        if let extraData = info.extraData, !extraData.isEmpty {
            let paddedSize = extraData.count + Int(AV_INPUT_BUFFER_PADDING_SIZE)
            let extradataPtr = av_malloc(paddedSize).assumingMemoryBound(to: UInt8.self)
            memset(extradataPtr, 0, paddedSize)
            extraData.withUnsafeBytes { srcPtr in
                memcpy(extradataPtr, srcPtr.baseAddress!, extraData.count)
            }
            
            codecCtx.pointee.extradata = extradataPtr
            codecCtx.pointee.extradata_size = Int32(extraData.count)
        }
        
        let openCodecRes = avcodec_open2(codecCtx, codec, nil)
        if openCodecRes < 0 {
            print("RTSPStreamManager - ❌ Aggressive open: avcodec_open2 failed: \(av_err2str(openCodecRes))")
            fallbackIfNeeded(url: url, transport: transport, useHWAccel: useHWAccel, whereFailed: "avcodec_open2_aggressive")
            return
        }
        
        // Allocate frame/packet
        frame = av_frame_alloc()
        packet = av_packet_alloc()
        
        print("RTSPStreamManager - ✅ Aggressive open success. Beginning decode loop.")
        decodeFailureCount = 0
        isRunning = true
        startDecodingLoop(url: url, transport: transport, useHWAccel: useHWAccel)
    }
    
    // MARK: - Fallback Logic
    
    private func fallbackIfNeeded(url: String, transport: RTSPTransport, useHWAccel: Bool, whereFailed: String) {
        // Only fallback if we haven't used fallback yet, and we had a cachedRTSPInfo
        if fallbackAllowed && cachedRTSPInfo != nil {
            print("RTSPStreamManager - ⚠️ Fallback triggered after \(whereFailed). Clearing cached info & re-opening with full analysis.")
            fallbackAllowed = false
            cachedRTSPInfo = nil
            cleanupResources()
            openStreamDefault(url: url, transport: transport, useHWAccel: useHWAccel)
        } else {
            print("RTSPStreamManager - ❌ Fallback not possible or no cached info. Stopping here.")
        }
    }
    
    // MARK: - Decode Loop
    
    private func startDecodingLoop(url: String, transport: RTSPTransport, useHWAccel: Bool) {
        print("RTSPStreamManager - Starting decode loop for: \(url)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                print("RTSPStreamManager - ❌ Decode loop aborted - self was nil")
                return
            }
            
            while self.isRunning {
                if !self.readNextFrame() {
                    self.decodeFailureCount += 1
                    // If we detect repeated failures early => fallback
                    if self.fallbackAllowed,
                       self.cachedRTSPInfo != nil,
                       self.decodeFailureCount >= self.maxEarlyFailuresBeforeFallback {
                        
                        print("RTSPStreamManager - ⚠️ Too many early decode failures, clearing cached info, fallback to default.")
                        self.stopStream()
                        self.cachedRTSPInfo = nil
                        self.fallbackAllowed = false
                        
                        // Try again with default
                        self.openStreamDefault(url: url, transport: transport, useHWAccel: useHWAccel)
                        break
                    }
                    
                    print("RTSPStreamManager - sleeping 0.5 for decode failure")
                    Thread.sleep(forTimeInterval: 0.5)
                } else {
                    self.decodeFailureCount = 0
                }
                
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
    
    private func readNextFrame() -> Bool {
        guard let formatContext = formatContext,
              let codecContext = codecContext,
              let frame = frame,
              let packet = packet else {
            print("RTSPStreamManager - Nil contexts in readNextFrame")
            return false
        }
        
        // Reset packet before reading
        av_packet_unref(packet)
        
        // Guard against invalid state
        guard isRunning else { return false }
        
        // Read frame with additional error handling
        let readResult = av_read_frame(formatContext, packet)
        if readResult < 0 {
            switch readResult {
            case AVERROR_EOF:
                print("RTSPStreamManager - End of stream reached")
                stopStream()
            case AVERROR(EAGAIN):
                // Resource temporarily unavailable, can retry
                return false
            case AVERROR(EINVAL):
                print("RTSPStreamManager - Invalid argument error in av_read_frame")
                return false
            case AVERROR(EIO):
                print("RTSPStreamManager - I/O error in av_read_frame")
                return false
            default:
                print("RTSPStreamManager - Error reading frame: \(av_err2str(readResult))")
                return false
            }
            return false
        }
        
        // Ignore packets that aren't video
        if packet.pointee.stream_index != 0 {  // Assuming video is stream 0
            av_packet_unref(packet)
            return true
        }
        
        let sendResult = avcodec_send_packet(codecContext, packet)
        if sendResult < 0 {
            print("RTSPStreamManager - Error sending packet: \(av_err2str(sendResult))")
            av_packet_unref(packet)
            return false
        }
        
        while true {
            let receiveResult = avcodec_receive_frame(codecContext, frame)
            if receiveResult == AVERROR(EAGAIN) || receiveResult == AVERROR_EOF {
                break
            } else if receiveResult < 0 {
                print("RTSPStreamManager - Error receiving frame: \(av_err2str(receiveResult))")
                break
            }
            
            convertFrameToImage(frame)
            av_frame_unref(frame)
        }
        
        av_packet_unref(packet)
        return true
    }
    
    // MARK: - Frame Conversion
    
    private func convertFrameToImage(_ frame: UnsafeMutablePointer<AVFrame>) {
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)
        
        guard let rgbFrame = av_frame_alloc() else { return }
        defer {
            var temp: UnsafeMutablePointer<AVFrame>? = rgbFrame
            av_frame_free(&temp)
        }
        
        rgbFrame.pointee.format = Int32(AV_PIX_FMT_RGB24.rawValue)
        rgbFrame.pointee.width  = Int32(width)
        rgbFrame.pointee.height = Int32(height)
        
        guard av_frame_get_buffer(rgbFrame, 0) >= 0 else { return }
        
        guard let swsContext = sws_getContext(
            Int32(width),
            Int32(height),
            AVPixelFormat(frame.pointee.format),
            Int32(width),
            Int32(height),
            AV_PIX_FMT_RGB24,
            SWS_BILINEAR,
            nil,
            nil,
            nil
        ) else { return }
        
        defer { sws_freeContext(swsContext) }
        
        // src/dst pointers
        var dstDataPointers: [UnsafeMutablePointer<UInt8>?] = [
            rgbFrame.pointee.data.0,
            rgbFrame.pointee.data.1,
            rgbFrame.pointee.data.2,
            rgbFrame.pointee.data.3,
            rgbFrame.pointee.data.4,
            rgbFrame.pointee.data.5,
            rgbFrame.pointee.data.6,
            rgbFrame.pointee.data.7
        ]
        let srcDataPointers: [UnsafePointer<UInt8>?] = [
            UnsafePointer(frame.pointee.data.0),
            UnsafePointer(frame.pointee.data.1),
            UnsafePointer(frame.pointee.data.2),
            UnsafePointer(frame.pointee.data.3),
            UnsafePointer(frame.pointee.data.4),
            UnsafePointer(frame.pointee.data.5),
            UnsafePointer(frame.pointee.data.6),
            UnsafePointer(frame.pointee.data.7)
        ]
        
        let srcLinesize: [Int32] = [
            frame.pointee.linesize.0,
            frame.pointee.linesize.1,
            frame.pointee.linesize.2,
            frame.pointee.linesize.3,
            frame.pointee.linesize.4,
            frame.pointee.linesize.5,
            frame.pointee.linesize.6,
            frame.pointee.linesize.7
        ]
        let dstLinesize: [Int32] = [
            rgbFrame.pointee.linesize.0,
            rgbFrame.pointee.linesize.1,
            rgbFrame.pointee.linesize.2,
            rgbFrame.pointee.linesize.3,
            rgbFrame.pointee.linesize.4,
            rgbFrame.pointee.linesize.5,
            rgbFrame.pointee.linesize.6,
            rgbFrame.pointee.linesize.7
        ]
        
        let result = sws_scale(
            swsContext,
            srcDataPointers,
            srcLinesize,
            0,
            Int32(height),
            &dstDataPointers,
            dstLinesize
        )
        guard result >= 0 else { return }
        
        // Create UIImage
        let bytesPerRow = width * 3
        guard let rgbData = rgbFrame.pointee.data.0 else { return }
        let data = Data(bytes: rgbData, count: height * bytesPerRow)
        
        guard let provider = CGDataProvider(data: data as CFData) else { return }
        if let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) {
            DispatchQueue.main.async {
                self.currentFrame = UIImage(cgImage: cgImage)
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupResources() {
        if let codecContext = codecContext {
            // If we allocated extradata, free it
            if let ptr = codecContext.pointee.extradata {
                av_free(ptr)
                codecContext.pointee.extradata = nil
            }
            var tempCodecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&tempCodecContext)
            self.codecContext = nil
        }
        
        if let formatContext = formatContext {
            var tempFormatContext: UnsafeMutablePointer<AVFormatContext>? = formatContext
            avformat_close_input(&tempFormatContext)
            self.formatContext = nil
        }
        
        if let frame = frame {
            var tempFrame: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&tempFrame)
            self.frame = nil
        }
        
        if let packet = packet {
            var tempPacket: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&tempPacket)
            self.packet = nil
        }
        
        DispatchQueue.main.async {
            self.currentFrame = nil
        }
    }
}

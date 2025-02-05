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

class RTSPStreamManager: ObservableObject {
    @Published var currentFrame: UIImage?
    var currentStreamURL: String?
    
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var isRunning = false
    
    // MARK: - AVDictionary: Default vs Fast Startup
    
    /// Generic / default dictionary for stream open.
    private func defaultDictionary(transport: RTSPTransport, useHWAccel: Bool) -> OpaquePointer? {
        var dict: OpaquePointer? = nil
        
        // Example defaults (fill with your own or existing approach)
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
    
    /// More aggressive / fast-start dictionary. Possibly skip or reduce analysis.
    private func fastStartupDictionary(from info: RTSPInfo?, transport: RTSPTransport, useHWAccel: Bool) -> OpaquePointer? {
        var dict: OpaquePointer? = nil
        
        av_dict_set(&dict, "rtsp_transport", transport.rawValue, 0)
        
        // For fast start, we might reduce or skip analysis if we trust prior info:
        // If we have known metadata, you could do these extremes:
        av_dict_set(&dict, "analyzeduration", "100000", 0) // 0.1s
        av_dict_set(&dict, "probesize", "100000", 0)       // 100 KB
        av_dict_set(&dict, "fflags", "nobuffer", 0)
        av_dict_set(&dict, "flags", "low_delay", 0)
        
        // Possibly also reduce "stimeout" or "max_delay" further
        av_dict_set(&dict, "stimeout", "1000000", 0) // 1 second
        av_dict_set(&dict, "max_delay", "250000", 0) // 0.25 seconds
        
        // Optional hardware accel placeholder
        if useHWAccel {
            av_dict_set(&dict, "hwaccel", "videotoolbox", 0)
        }
        
        return dict
    }
    
    // MARK: - Public Stream API
    
    /// Start streaming. Decide if we use a default dictionary or a 'fast startup' dictionary
    /// based on whether `cameraConfig.streamInfo` is available or not.
    func startStream(cameraConfig: inout CameraConfig,
                     transport: RTSPTransport = .tcp,
                     useHWAccel: Bool = false) {
        print("RTSPStreamManager - Starting stream for \(cameraConfig.url)")
        print("RTSPStreamManager - Using \(cameraConfig.streamInfo != nil ? "fast startup" : "default") configuration")
        
        let url = cameraConfig.url
        currentStreamURL = url
        
        // Move published property update to main thread
        DispatchQueue.main.async {
            self.currentStreamURL = url
        }
        guard !url.contains("Not set") else { return }
        
        // Change from let to var for options
        var options: OpaquePointer? = (cameraConfig.streamInfo != nil)
            ? fastStartupDictionary(from: cameraConfig.streamInfo, transport: transport, useHWAccel: useHWAccel)
            : defaultDictionary(transport: transport, useHWAccel: useHWAccel)
        
        // Initialize FFmpeg format context
        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        let openRes = avformat_open_input(&formatCtx, url, nil, &options)
        av_dict_free(&options) // Always free dictionary after open
        
        guard openRes >= 0, let validFormatCtx = formatCtx else {
            print("RTSPStreamManager - ❌ Failed to open input: \(url)")
            return
        }
        
        self.formatContext = validFormatCtx
        
        // We still might want to call find_stream_info. For a truly "fast" approach,
        // you could skip or reduce it if `cameraConfig.streamInfo` is not nil, but
        // here's the simpler approach:
        if avformat_find_stream_info(validFormatCtx, nil) < 0 {
            print("RTSPStreamManager - ❌ Failed to find stream info")
            return
        }
        print("RTSPStreamManager - ✅ Stream info found")
        
        // Find the video stream
        var videoStreamIndex: Int32 = -1
        for i in 0..<Int(validFormatCtx.pointee.nb_streams) {
            let stream = validFormatCtx.pointee.streams[i]
            if stream?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int32(i)
                break
            }
        }
        
        guard videoStreamIndex != -1 else {
            print("RTSPStreamManager - No video stream found")
            return
        }
        
        // Set up decoder
        guard let codecParams = validFormatCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar else {
            print("RTSPStreamManager - Failed to get codec parameters")
            return
        }
        guard let codec = avcodec_find_decoder(codecParams.pointee.codec_id) else {
            print("RTSPStreamManager - Failed to find decoder")
            return
        }
        
        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("RTSPStreamManager - Failed to allocate codec context")
            return
        }
        
        guard avcodec_parameters_to_context(codecCtx, codecParams) >= 0 else {
            print("RTSPStreamManager - Failed to set codec params")
            return
        }
        
        // If useHWAccel, you might do additional setup here (hw frames context, etc.).
        // This snippet only illustrates a dictionary-based approach.
        
        guard avcodec_open2(codecCtx, codec, nil) >= 0 else {
            print("RTSPStreamManager - Failed to open codec")
            return
        }
        
        // Allocate frame and packet
        frame = av_frame_alloc()
        packet = av_packet_alloc()
        
        // Cache discovered stream info for next time
        let discoveredCodecID = Int32(codecParams.pointee.codec_id.rawValue)
        let discoveredWidth = Int(codecParams.pointee.width)
        let discoveredHeight = Int(codecParams.pointee.height)
        
        // For example, store or update the cameraConfig.streamInfo:
        let newInfo = RTSPInfo(codecID: discoveredCodecID,
                               width: discoveredWidth,
                               height: discoveredHeight)
        cameraConfig.streamInfo = newInfo
        
        print("RTSPStreamManager - ✅ Stream setup complete, beginning decode loop")
        isRunning = true
        startDecodingLoop()
    }
    
    func restartStream(cameraConfig: inout CameraConfig,
                       transport: RTSPTransport = .tcp,
                       useHWAccel: Bool = false) {
        print("RTSPStreamManager - Restarting stream: \(cameraConfig.url)")
        stopStream()
        startStream(cameraConfig: &cameraConfig, transport: transport, useHWAccel: useHWAccel)
    }
    
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
        Thread.sleep(forTimeInterval: 0.1)
        
        if let codecContext = codecContext {
            var tempCodecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
            avcodec_free_context(&tempCodecContext)
        }
        
        if let formatContext = formatContext {
            var tempFormatContext: UnsafeMutablePointer<AVFormatContext>? = formatContext
            avformat_close_input(&tempFormatContext)
            self.formatContext = nil
        }
        
        if let frame = frame {
            var tempFrame: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&tempFrame)
        }
        
        if let packet = packet {
            var tempPacket: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&tempPacket)
        }
        
        // Clear the current frame
        DispatchQueue.main.async {
            self.currentFrame = nil
        }
        
        codecContext = nil
        frame = nil
        packet = nil
        
        print("RTSPStreamManager - ✅ Stream stopped and resources cleaned up")
    }
    
    deinit {
        stopStream()
    }
    
    // MARK: - Internal Decoding Loop
    
    private func startDecodingLoop() {
        print("RTSPStreamManager - Starting decode loop")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                print("RTSPStreamManager - ❌ Failed to start decode loop - self was nil")
                return
            }
            
            while self.isRunning {
                if !self.readNextFrame() {
                    // Only log if there's an actual failure, not just a temporary EAGAIN
//                    if self.isRunning {
//                        print("RTSPStreamManager - ⚠️ Frame read failed, will retry")
//                    }
                    Thread.sleep(forTimeInterval: 0.5)
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
    
    private func readNextFrame() -> Bool {
        guard let formatContext = formatContext,
              let codecContext = codecContext,
              let frame = frame,
              let packet = packet else {
            return false
        }
        
        let readResult = av_read_frame(formatContext, packet)
        if readResult < 0 {
            switch readResult {
            case AVERROR_EOF:
                print("RTSPStreamManager - End of stream reached")
                stopStream()
            case AVERROR(EAGAIN):
                // Resource temporarily unavailable, can retry
                return false
            default:
                print("RTSPStreamManager - Error reading frame: \(av_err2str(readResult))")
                return false
            }
            return false
        }
        
        let sendResult = avcodec_send_packet(codecContext, packet)
        if sendResult < 0 {
            av_packet_unref(packet)
            return false
        }
        
        let receiveResult = avcodec_receive_frame(codecContext, frame)
        if receiveResult >= 0 {
            convertFrameToImage(frame)
        } else if receiveResult != AVERROR(EAGAIN) {
            print("RTSPStreamManager - Error receiving frame: \(av_err2str(receiveResult))")
        }
        
        av_packet_unref(packet)
        return true
    }
    
    // MARK: - Convert Frame to UIImage
    
    private func convertFrameToImage(_ frame: UnsafeMutablePointer<AVFrame>) {
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)
        
        guard let rgbFrame = av_frame_alloc() else { return }
        defer {
            var temp: UnsafeMutablePointer<AVFrame>? = rgbFrame
            av_frame_free(&temp)
        }
        
        rgbFrame.pointee.format = Int32(AV_PIX_FMT_RGB24.rawValue)
        rgbFrame.pointee.width = Int32(width)
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
        
        // Set up src/dst pointers
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
    
    func startStreamOptimized(
        camera: CameraConfig,
        transport: RTSPTransport = .tcp,
        useHWAccel: Bool = false,
        onStreamInfoUpdate: ((CameraConfig) -> Void)? = nil
    ) {
        print("RTSPStreamManager - Safe start requested for camera: \(camera.url)")
        var mutableCamera = camera
        startStream(cameraConfig: &mutableCamera, transport: transport, useHWAccel: useHWAccel)
        
        if mutableCamera.streamInfo != camera.streamInfo {
            print("RTSPStreamManager - Stream info updated, notifying callback")
            onStreamInfoUpdate?(mutableCamera)
        }
    }
    
    func restartStreamOptimized(
        camera: CameraConfig,
        transport: RTSPTransport = .tcp,
        useHWAccel: Bool = false,
        onStreamInfoUpdate: ((CameraConfig) -> Void)? = nil
    ) {
        print("RTSPStreamManager - Safe restart requested for camera: \(camera.url)")
        var mutableCamera = camera
        restartStream(cameraConfig: &mutableCamera, transport: transport, useHWAccel: useHWAccel)
        
        if mutableCamera.streamInfo != camera.streamInfo {
            print("RTSPStreamManager - Stream info updated during restart, notifying callback")
            onStreamInfoUpdate?(mutableCamera)
        }
    }
}

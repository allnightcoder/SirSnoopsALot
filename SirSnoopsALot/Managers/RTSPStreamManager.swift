import Foundation
import UIKit
import CoreGraphics

// Add FFmpeg imports and constants
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

class RTSPStreamManager: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var currentStreamURL: String?
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var isRunning = false
    
    func startStream(url: String) {
        currentStreamURL = url
        guard !url.contains("Not set") else { return }
        
        // Initialize FFmpeg components
        var formatContext: UnsafeMutablePointer<AVFormatContext>? = nil
        guard avformat_open_input(&formatContext, url, nil, nil) >= 0 else {
            print("RTSPStreamManager - Failed to open input")
            return
        }
        self.formatContext = formatContext
        
        guard avformat_find_stream_info(formatContext, nil) >= 0 else {
            print("RTSPStreamManager - Failed to find stream info")
            return
        }
        
        // Find the video stream
        var videoStreamIndex: Int32 = -1
        guard let formatCtx = formatContext else { return }
        for i in 0..<Int(formatCtx.pointee.nb_streams) {
            let stream = formatCtx.pointee.streams[Int(i)]
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
        guard let formatCtx = formatContext,
              let codecParams = formatCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar else {
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
        
        guard avcodec_open2(codecCtx, codec, nil) >= 0 else {
            print("RTSPStreamManager - Failed to open codec")
            return
        }
        
        // Allocate frame and packet
        frame = av_frame_alloc()
        packet = av_packet_alloc()
        
        isRunning = true
        startDecodingLoop()
    }
    
    private func startDecodingLoop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                if !self.readNextFrame() {
                    // If reading fails, wait a bit longer before retry
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                Thread.sleep(forTimeInterval: 0.01) // ~10fps
            }
        }
    }
    
    private func readNextFrame() -> Bool {
        guard let formatContext = formatContext,
              let codecContext = codecContext,
              let frame = frame,
              let packet = packet else { return false }
        
        let readResult = av_read_frame(formatContext, packet)
        if readResult < 0 {
            // Handle specific error cases
            switch readResult {
            case AVERROR_EOF:  // Now both sides of comparison are Int32
                print("RTSPStreamManager - End of stream reached")
                stopStream()
            case AVERROR(EAGAIN):
                // Resource temporarily unavailable, can retry
                return false
            default:
                let errorString = String(cString: av_err2str(readResult))
                print("RTSPStreamManager - Error reading frame: \(errorString)")
                return false
            }
            return false
        }
        
        let sendResult = avcodec_send_packet(codecContext, packet)
        if sendResult < 0 {
            let errorString = String(cString: av_err2str(sendResult))
            print("RTSPStreamManager - Error sending packet: \(errorString)")
            av_packet_unref(packet)
            return false
        }
        
        let receiveResult = avcodec_receive_frame(codecContext, frame)
        if receiveResult >= 0 {
            convertFrameToImage(frame)
        } else if receiveResult != AVERROR(EAGAIN) {
            let errorString = String(cString: av_err2str(receiveResult))
            print("RTSPStreamManager - Error receiving frame: \(errorString)")
        }
        
        av_packet_unref(packet)
        return true
    }
    
    private func convertFrameToImage(_ frame: UnsafeMutablePointer<AVFrame>) {
        // Convert frame to RGB format
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)
        
        guard let rgbFrame = av_frame_alloc() else { return }
        defer { 
            var tempFrame: UnsafeMutablePointer<AVFrame>? = rgbFrame
            av_frame_free(&tempFrame)
        }
        
        rgbFrame.pointee.format = Int32(AV_PIX_FMT_RGB24.rawValue)
        rgbFrame.pointee.width = Int32(width)
        rgbFrame.pointee.height = Int32(height)
        
        guard av_frame_get_buffer(rgbFrame, 0) >= 0 else { return }
        
        guard let swsContext = sws_getContext(
            Int32(width), Int32(height), AVPixelFormat(frame.pointee.format),
            Int32(width), Int32(height), AV_PIX_FMT_RGB24,
            SWS_BILINEAR, nil, nil, nil) else { return }
        defer { sws_freeContext(swsContext) }
        
        // Create arrays of mutable pointers for destination data
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
        
        // Create arrays of const pointers for source data
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

        let result = sws_scale(swsContext,
                             srcDataPointers,
                             srcLinesize,
                             0, Int32(height),
                             &dstDataPointers,
                             dstLinesize)
        
        guard result >= 0 else { return }
        
        // Create UIImage from RGB data
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
    
    func stopStream() {
        guard currentStreamURL != nil else { return }
        
        print("RTSPStreamManager - Stopping stream: \(currentStreamURL ?? "None")")
        isRunning = false
        currentStreamURL = nil
        
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
    }
    
    deinit {
        stopStream()
    }
} 

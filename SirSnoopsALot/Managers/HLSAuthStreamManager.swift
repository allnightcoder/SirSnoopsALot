import Foundation
import UIKit
import CoreGraphics

/// Manages an HLS stream using FFmpeg with Bearer token authentication
/// Based on RTSPStreamManager but simplified for HLS playback
class HLSAuthStreamManager: ObservableObject {
    @Published var currentFrame: UIImage?

    private(set) var currentStreamURL: String?

    // Internal FFmpeg contexts
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var packet: UnsafeMutablePointer<AVPacket>?

    private var isRunning = false
    private var videoStreamIndex = Int32(-1)

    // Minimal logging flags
    private var didLogVTReady = false
    private var didLogVTActive = false
    private var didLogSWActive = false

    // MARK: - Public API

    /// Start streaming HLS with Bearer token authentication
    func startStream(url: String, authToken: String) {
        DispatchQueue.main.async {
            self.currentStreamURL = url
        }

        print("HLSAuthStreamManager - Starting HLS stream: \(url)")
        openStream(url: url, authToken: authToken)
    }

    /// Stop the current stream
    func stopStream() {
        guard currentStreamURL != nil else {
            print("HLSAuthStreamManager - Stop requested but no active stream")
            return
        }

        print("HLSAuthStreamManager - Stopping stream")
        isRunning = false

        DispatchQueue.main.async {
            self.currentStreamURL = nil
        }

        Thread.sleep(forTimeInterval: 0.2)
        cleanupResources()

        print("HLSAuthStreamManager - Stream stopped")
    }

    deinit {
        stopStream()
    }

    // MARK: - Stream Opening

    private func openStream(url: String, authToken: String) {
        // Set up options with authentication header
        var options: OpaquePointer? = nil
        let headerString = "Authorization: Bearer \(authToken)\r\n"
        av_dict_set(&options, "headers", headerString, 0)

        // HLS-specific settings for smooth playback
        av_dict_set(&options, "analyzeduration", "1000000", 0) // 1 second
        av_dict_set(&options, "probesize", "1000000", 0)        // 1 MB

        var formatContext: UnsafeMutablePointer<AVFormatContext>? = nil
        let openResult = avformat_open_input(&formatContext, url, nil, &options)
        av_dict_free(&options)

        guard openResult >= 0, let validCtx = formatContext else {
            print("HLSAuthStreamManager - ❌ Failed to open input: \(url), error: \(av_err2str(openResult))")
            return
        }
        self.formatContext = validCtx

        // Find stream info
        guard avformat_find_stream_info(validCtx, nil) >= 0 else {
            print("HLSAuthStreamManager - ❌ avformat_find_stream_info failed")
            cleanupResources()
            return
        }
        print("HLSAuthStreamManager - ✅ Found stream info")

        // Find video stream
        self.videoStreamIndex = Int32(-1)
        for i in 0..<Int(validCtx.pointee.nb_streams) {
            let stream = validCtx.pointee.streams[i]
            if stream?.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int32(i)
                break
            }
        }

        guard videoStreamIndex != -1 else {
            print("HLSAuthStreamManager - ❌ No video stream found")
            cleanupResources()
            return
        }
        print("HLSAuthStreamManager - Found video stream at index: \(videoStreamIndex)")

        guard let codecParams = validCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar else {
            print("HLSAuthStreamManager - ❌ Failed to get codec parameters")
            cleanupResources()
            return
        }

        print("""
        HLSAuthStreamManager - Video Info:
        - codec_id: \(codecParams.pointee.codec_id.rawValue)
        - width: \(codecParams.pointee.width)
        - height: \(codecParams.pointee.height)
        - format: \(codecParams.pointee.format)
        """)

        guard let codec = avcodec_find_decoder(codecParams.pointee.codec_id) else {
            print("HLSAuthStreamManager - ❌ Failed to find decoder")
            cleanupResources()
            return
        }

        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("HLSAuthStreamManager - ❌ Failed to alloc codec context")
            cleanupResources()
            return
        }

        guard avcodec_parameters_to_context(codecCtx, codecParams) >= 0 else {
            print("HLSAuthStreamManager - ❌ Failed avcodec_parameters_to_context")
            cleanupResources()
            return
        }

        // Enable VideoToolbox hardware acceleration
        let vtSetup = ssa_setup_videotoolbox(codecCtx)
        if vtSetup >= 0, !didLogVTReady {
            print("HLSAuthStreamManager - ✅ VideoToolbox hwaccel available")
            didLogVTReady = true
        }

        guard avcodec_open2(codecCtx, codec, nil) >= 0 else {
            print("HLSAuthStreamManager - ❌ Failed avcodec_open2")
            cleanupResources()
            return
        }

        // Allocate frame/packet
        frame = av_frame_alloc()
        packet = av_packet_alloc()

        print("HLSAuthStreamManager - ✅ Stream opened successfully, starting decode loop")
        isRunning = true
        startDecodingLoop()
    }

    // MARK: - Decode Loop

    private func startDecodingLoop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            while self.isRunning {
                if !self.readNextFrame() {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                Thread.sleep(forTimeInterval: 0.033) // ~30fps
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
            if readResult == AVERROR_EOF {
                print("HLSAuthStreamManager - End of stream")
                stopStream()
            }
            return false
        }

        // Only process video packets
        if packet.pointee.stream_index != self.videoStreamIndex {
            av_packet_unref(packet)
            return true
        }

        guard avcodec_send_packet(codecContext, packet) >= 0 else {
            av_packet_unref(packet)
            return false
        }

        let receiveResult = avcodec_receive_frame(codecContext, frame)
        if receiveResult >= 0 {
            // Handle hardware-decoded frames
            if AVPixelFormat(rawValue: frame.pointee.format) == AV_PIX_FMT_VIDEOTOOLBOX {
                if !didLogVTActive {
                    print("HLSAuthStreamManager - Using VideoToolbox hardware decoding")
                    didLogVTActive = true
                }
                if let swFrame = av_frame_alloc() {
                    if av_hwframe_transfer_data(swFrame, frame, 0) == 0 {
                        convertFrameToImage(swFrame)
                    }
                    var tmp: UnsafeMutablePointer<AVFrame>? = swFrame
                    av_frame_free(&tmp)
                }
            } else {
                if !didLogSWActive {
                    print("HLSAuthStreamManager - Using software decoding")
                    didLogSWActive = true
                }
                convertFrameToImage(frame)
            }
        }

        av_packet_unref(packet)
        return true
    }

    // MARK: - Frame Conversion (copied from RTSPStreamManager)

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

        self.videoStreamIndex = -1
        self.didLogVTReady = false
        self.didLogVTActive = false
        self.didLogSWActive = false

        DispatchQueue.main.async {
            self.currentFrame = nil
        }
    }
}

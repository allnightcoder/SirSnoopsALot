import Foundation
import UIKit
import CoreGraphics

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
final class RTSPStreamManager: ObservableObject {
    @Published var currentFrame: UIImage?

    private struct StreamParameters {
        let url: String
        let transport: RTSPTransport
        let useHWAccel: Bool
    }

    private(set) var currentStreamURL: String?

    private let ffQueue = DispatchQueue(label: "com.sirsnoopsalot.rtsp.ffmpeg.serial", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "com.sirsnoopsalot.rtsp.state", attributes: .concurrent)

    private var loopGroup = DispatchGroup()
    private var abortFlag = FFAbort(flag: 0)

    private var streamParameters: StreamParameters?
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var videoStreamIndex: Int32 = -1
    private var isDecoding = false

    private var cachedRTSPInfo: RTSPInfo?
    private var fallbackAllowed = true
    private var decodeFailureCount = 0
    private let maxEarlyFailuresBeforeFallback = 5

    private var onStreamInfoUpdate: ((RTSPInfo?) -> Void)?

    private var didLogVTReady = false
    private var didLogVTActive = false
    private var didLogSWActive = false

    private var _pendingRestartAfterLoop = false
    private var _shouldStopCompletely = false

    private func setPendingRestart(_ value: Bool) {
        stateQueue.sync(flags: .barrier) {
            self._pendingRestartAfterLoop = value
        }
    }

    private func getPendingRestart() -> Bool {
        stateQueue.sync { _pendingRestartAfterLoop }
    }

    private func setShouldStopCompletely(_ value: Bool) {
        stateQueue.sync(flags: .barrier) {
            self._shouldStopCompletely = value
        }
    }

    private func getShouldStopCompletely() -> Bool {
        stateQueue.sync { _shouldStopCompletely }
    }

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

        if useHWAccel {
            av_dict_set(&dict, "hwaccel", "videotoolbox", 0)
        }
        return dict
    }

    // MARK: - Public API

    func startStream(
        url: String,
        initialInfo: RTSPInfo? = nil,
        transport: RTSPTransport = .tcp,
        useHWAccel: Bool = false,
        onStreamInfoUpdate: ((RTSPInfo?) -> Void)? = nil
    ) {
        self.currentStreamURL = url
        DispatchQueue.main.async {
            self.currentStreamURL = url
        }

        self.cachedRTSPInfo = initialInfo
        self.onStreamInfoUpdate = onStreamInfoUpdate
        self.fallbackAllowed = true
        self.decodeFailureCount = 0
        self.streamParameters = StreamParameters(url: url, transport: transport, useHWAccel: useHWAccel)

        setPendingRestart(false)
        setShouldStopCompletely(false)

        ffQueue.async { [weak self] in
            guard let self else { return }
            self.abortFlag.flag = 0
            self.openCurrentStreamLocked()
        }
    }

    /// Stop the current stream.
    func stopStream() {
        guard currentStreamURL != nil || isDecoding else {
            print("RTSPStreamManager - Stop requested but no active stream")
            return
        }

        print("RTSPStreamManager - Stopping stream: \(currentStreamURL ?? "None")")
        setShouldStopCompletely(true)
        setPendingRestart(false)
        abortFlag.flag = 1

        let waitResult = loopGroup.wait(timeout: .now() + 2)
        if waitResult == .timedOut {
            print("RTSPStreamManager - ⚠️ Timed out waiting for decode loop to exit")
        }

        ffQueue.async { [weak self] in
            guard let self else { return }
            if !self.isDecoding {
                self.safeTearDownLocked()
            }
            self.abortFlag.flag = 0
            self.isDecoding = false
            self.setShouldStopCompletely(false)
            self.setPendingRestart(false)
        }

        DispatchQueue.main.async {
            self.currentStreamURL = nil
        }

        print("RTSPStreamManager - ✅ Stream stopped and resources cleaned up")
    }

    deinit {
        stopStream()
    }

    // MARK: - Stream Opening

    private func openCurrentStreamLocked() {
        guard let params = streamParameters else { return }

        if let info = cachedRTSPInfo {
            print("RTSPStreamManager - Using AGGRESSIVE open with cached info: \(info.debugDescription)")
            openStreamAggressiveLocked(params: params, info: info)
        } else {
            print("RTSPStreamManager - No cached info, calling openStreamDefault")
            openStreamDefaultLocked(params: params)
        }
    }

    private func openStreamDefaultLocked(params: StreamParameters) {
        var options: OpaquePointer? = defaultDictionary(transport: params.transport, useHWAccel: params.useHWAccel)

        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        let openResult = avformat_open_input(&formatCtx, params.url, nil, &options)
        av_dict_free(&options)

        guard openResult >= 0, let validCtx = formatCtx else {
            print("RTSPStreamManager - Failed to open input: \(params.url) error=\(av_err2str(openResult))")
            return
        }
        formatContext = validCtx
        ff_install_interrupt_cb(validCtx, &abortFlag)

        guard avformat_find_stream_info(validCtx, nil) >= 0 else {
            print("RTSPStreamManager - ❌ openStreamDefault: avformat_find_stream_info failed")
            safeTearDownLocked()
            return
        }
        print("RTSPStreamManager - ✅ openStreamDefault: found stream info")

        videoStreamIndex = -1
        for i in 0..<Int(validCtx.pointee.nb_streams) {
            if let stream = validCtx.pointee.streams[i],
               stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int32(i)
                break
            }
        }

        guard videoStreamIndex != -1,
              let codecParams = validCtx.pointee.streams[Int(videoStreamIndex)]?.pointee.codecpar else {
            print("RTSPStreamManager - No video stream found in default open")
            safeTearDownLocked()
            return
        }

        guard let codec = avcodec_find_decoder(codecParams.pointee.codec_id) else {
            print("RTSPStreamManager - Failed to find decoder in default open")
            safeTearDownLocked()
            return
        }

        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("RTSPStreamManager - Failed to alloc codec context in default open")
            safeTearDownLocked()
            return
        }

        guard avcodec_parameters_to_context(codecCtx, codecParams) >= 0 else {
            print("RTSPStreamManager - Failed avcodec_parameters_to_context in default open")
            safeTearDownLocked()
            return
        }

        let vtSetupDefault = ssa_setup_videotoolbox(codecCtx)
        if vtSetupDefault >= 0, !didLogVTReady {
            print("RTSPStreamManager - VideoToolbox hwaccel available (soft-enabled)")
            didLogVTReady = true
        }

        let resCodecOpen = avcodec_open2(codecCtx, codec, nil)
        guard resCodecOpen >= 0 else {
            print("RTSPStreamManager - Failed avcodec_open2 in default open: \(av_err2str(resCodecOpen))")
            safeTearDownLocked()
            return
        }

        // Cache discovered stream info for next time
        let discoveredCodecID = Int32(codecParams.pointee.codec_id.rawValue)
        let discoveredWidth = Int(codecParams.pointee.width)
        let discoveredHeight = Int(codecParams.pointee.height)
        let discoveredFormat = Int(codecParams.pointee.format)
        let discoveredBitRate = Int64(codecParams.pointee.bit_rate)
        let discoveredVideoStreamIndex = videoStreamIndex

        var extradataData: Data? = nil
        if codecParams.pointee.extradata_size > 0,
           let ptr = codecParams.pointee.extradata {
            let size = Int(codecParams.pointee.extradata_size)
            extradataData = Data(bytes: ptr, count: size)
        }

        let newInfo = RTSPInfo(codecID: discoveredCodecID,
                               width: discoveredWidth,
                               height: discoveredHeight,
                               format: discoveredFormat,
                               bitRate: discoveredBitRate,
                               videoStreamIndex: discoveredVideoStreamIndex,
                               extraData: extradataData)

        DispatchQueue.main.async {
            self.onStreamInfoUpdate?(newInfo)
        }

        if getShouldStopCompletely() {
            print("RTSPStreamManager - Stop requested before decode loop start; aborting default open")
            safeTearDownLocked()
            return
        }

        decodeFailureCount = 0
        isDecoding = true
        startDecodingLoopLocked(with: params)
    }

    private func openStreamAggressiveLocked(params: StreamParameters, info: RTSPInfo) {
        var options: OpaquePointer? = fastStartupDictionary(transport: params.transport, useHWAccel: params.useHWAccel)

        var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        let openRes = avformat_open_input(&formatCtx, params.url, nil, &options)
        av_dict_free(&options)

        guard openRes >= 0, let validFormatCtx = formatCtx else {
            print("RTSPStreamManager - ❌ Aggressive open: avformat_open_input failed: \(av_err2str(openRes))")
            fallbackAfterAggressiveFailureLocked(params: params, reason: "aggressive_open_input")
            return
        }
        formatContext = validFormatCtx
        ff_install_interrupt_cb(validFormatCtx, &abortFlag)

        guard validFormatCtx.pointee.nb_streams > 0 else {
            print("RTSPStreamManager - No streams found in aggressive open")
            fallbackAfterAggressiveFailureLocked(params: params, reason: "no_streams_aggressive")
            return
        }

        videoStreamIndex = info.videoStreamIndex

        let wantedCodecID = AVCodecID(UInt32(info.codecID))
        guard let codec = avcodec_find_decoder(wantedCodecID) else {
            print("RTSPStreamManager - ❌ Aggressive open: failed avcodec_find_decoder for \(info.codecID)")
            fallbackAfterAggressiveFailureLocked(params: params, reason: "find_decoder_aggressive")
            return
        }

        codecContext = avcodec_alloc_context3(codec)
        guard let codecCtx = codecContext else {
            print("RTSPStreamManager - ❌ Aggressive open: avcodec_alloc_context3 failed")
            fallbackAfterAggressiveFailureLocked(params: params, reason: "alloc_context_aggressive")
            return
        }

        codecCtx.pointee.codec_id = wantedCodecID
        codecCtx.pointee.width = Int32(info.width)
        codecCtx.pointee.height = Int32(info.height)

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

        let vtSetup = ssa_setup_videotoolbox(codecCtx)
        if vtSetup >= 0, !didLogVTReady {
            print("RTSPStreamManager - VideoToolbox hwaccel available (soft-enabled)")
            didLogVTReady = true
        }

        let openCodecRes = avcodec_open2(codecCtx, codec, nil)
        if openCodecRes < 0 {
            print("RTSPStreamManager - ❌ Aggressive open: avcodec_open2 failed: \(av_err2str(openCodecRes))")
            fallbackAfterAggressiveFailureLocked(params: params, reason: "avcodec_open2_aggressive")
            return
        }

        if getShouldStopCompletely() {
            print("RTSPStreamManager - Stop requested before decode loop start; aborting aggressive open")
            safeTearDownLocked()
            return
        }

        decodeFailureCount = 0
        isDecoding = true
        startDecodingLoopLocked(with: params)
    }

    private func fallbackAfterAggressiveFailureLocked(params: StreamParameters, reason: String) {
        guard fallbackAllowed else {
            print("RTSPStreamManager - ❌ Fallback not possible (already used) after \(reason)")
            safeTearDownLocked()
            return
        }

        print("RTSPStreamManager - ⚠️ Fallback triggered after \(reason). Clearing cached info & re-opening with full analysis.")
        fallbackAllowed = false
        cachedRTSPInfo = nil
        safeTearDownLocked()
        openStreamDefaultLocked(params: params)
    }

    // MARK: - Decode Loop

    private func startDecodingLoopLocked(with params: StreamParameters) {
        guard let formatContext = formatContext,
              let codecContext = codecContext else {
            print("RTSPStreamManager - Nil contexts; cannot start decoding loop")
            safeTearDownLocked()
            return
        }

        if videoStreamIndex == -1 {
            print("RTSPStreamManager - Invalid video stream index")
            safeTearDownLocked()
            return
        }

        loopGroup.enter()

        ffQueue.async { [weak self] in
            guard let self else { return }
            self.runDecodeLoop(formatContext: formatContext, codecContext: codecContext, params: params)
        }
    }

    private func runDecodeLoop(formatContext: UnsafeMutablePointer<AVFormatContext>,
                                codecContext: UnsafeMutablePointer<AVCodecContext>,
                                params: StreamParameters) {
        guard let packet = av_packet_alloc(), let frame = av_frame_alloc() else {
            print("RTSPStreamManager - ❌ Failed to allocate packet/frame for decode loop")
            safeTearDownLocked()
            loopGroup.leave()
            return
        }

        defer {
            var pkt: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&pkt)
            var frm: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&frm)
        }

        while isDecoding {
            if abortFlag.flag != 0 {
                break
            }

            let readResult = av_read_frame(formatContext, packet)

            if readResult == fferr_eagain() {
                continue
            }

            if readResult == fferr_eof() {
                print("RTSPStreamManager - End of stream signaled by FFmpeg")
                break
            }

            if readResult < 0 {
                print("RTSPStreamManager - Error reading frame: \(av_err2str(readResult))")
                decodeFailureCount += 1
                if shouldFallbackDueToFailuresLocked() {
                    av_packet_unref(packet)
                    break
                }
                av_packet_unref(packet)
                continue
            }

            if packet.pointee.stream_index != videoStreamIndex {
                av_packet_unref(packet)
                continue
            }

            let sendResult = avcodec_send_packet(codecContext, packet)
            if sendResult < 0 {
                print("RTSPStreamManager - Error sending packet: \(av_err2str(sendResult))")
                decodeFailureCount += 1
                av_packet_unref(packet)
                if shouldFallbackDueToFailuresLocked() {
                    break
                }
                continue
            }

            while abortFlag.flag == 0 {
                let receiveResult = avcodec_receive_frame(codecContext, frame)
                if receiveResult == 0 {
                    decodeFailureCount = 0
                    handleDecodedFrame(frame)
                } else if receiveResult == fferr_eagain() {
                    break
                } else if receiveResult == fferr_eof() {
                    isDecoding = false
                    break
                } else {
                    print("RTSPStreamManager - Error receiving frame: \(av_err2str(receiveResult))")
                    decodeFailureCount += 1
                    break
                }
            }

            av_packet_unref(packet)

            if shouldFallbackDueToFailuresLocked() {
                break
            }

            if getShouldStopCompletely() {
                break
            }
        }

        isDecoding = false

        let shouldRestart = getPendingRestart()
        let shouldStop = getShouldStopCompletely()

        setPendingRestart(false)

        safeTearDownLocked()

        loopGroup.leave()

        abortFlag.flag = 0

        if shouldRestart && !shouldStop {
            print("RTSPStreamManager - Restarting stream with default analysis after fallback")
            openStreamDefaultLocked(params: params)
        } else if shouldStop {
            setShouldStopCompletely(false)
        }
    }

    private func shouldFallbackDueToFailuresLocked() -> Bool {
        guard fallbackAllowed, cachedRTSPInfo != nil else { return false }
        if decodeFailureCount < maxEarlyFailuresBeforeFallback {
            return false
        }

        print("RTSPStreamManager - ⚠️ Too many early decode failures, scheduling fallback to default stream open")
        fallbackAllowed = false
        cachedRTSPInfo = nil
        setPendingRestart(true)
        abortFlag.flag = 1
        return true
    }

    private func handleDecodedFrame(_ frame: UnsafeMutablePointer<AVFrame>) {
        if AVPixelFormat(rawValue: frame.pointee.format) == AV_PIX_FMT_VIDEOTOOLBOX {
            if !didLogVTActive {
                print("RTSPStreamManager - Using VideoToolbox hardware decoding")
                didLogVTActive = true
            }
            guard let swFrame = av_frame_alloc() else { return }
            defer {
                var tmp: UnsafeMutablePointer<AVFrame>? = swFrame
                av_frame_free(&tmp)
            }
            if av_hwframe_transfer_data(swFrame, frame, 0) == 0 {
                convertFrameToImage(swFrame)
            }
        } else {
            if !didLogSWActive {
                print("RTSPStreamManager - Using software decoding")
                didLogSWActive = true
            }
            convertFrameToImage(frame)
        }
    }

    // MARK: - Frame Conversion

    private func convertFrameToImage(_ frame: UnsafeMutablePointer<AVFrame>) {
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)

        guard width > 0, height > 0 else { return }

        if frame.pointee.linesize.0 < 0 {
            // Unsupported negative stride; skip frame.
            return
        }

        guard let rgbFrame = av_frame_alloc() else { return }
        defer {
            var tmp: UnsafeMutablePointer<AVFrame>? = rgbFrame
            av_frame_free(&tmp)
        }

        let imageAllocResult = withUnsafeMutablePointer(to: &rgbFrame.pointee.data.0) { dataPtr -> Int32 in
            return withUnsafeMutablePointer(to: &rgbFrame.pointee.linesize.0) { linesizePtr -> Int32 in
                av_image_alloc(dataPtr, linesizePtr, Int32(width), Int32(height), AV_PIX_FMT_RGB24, 1)
            }
        }
        guard imageAllocResult >= 0 else { return }
        defer { av_freep(&rgbFrame.pointee.data.0) }

        guard let swsContext = sws_getContext(
            Int32(width),
            Int32(height),
            AVPixelFormat(rawValue: frame.pointee.format),
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

        let result = dstDataPointers.withUnsafeMutableBufferPointer { dstBuffer -> Int32 in
            guard let dstBase = dstBuffer.baseAddress else { return -1 }
            return srcDataPointers.withUnsafeBufferPointer { srcBuffer -> Int32 in
                guard let srcBase = srcBuffer.baseAddress else { return -1 }
                return srcLinesize.withUnsafeBufferPointer { srcLineBuffer -> Int32 in
                    guard let srcLineBase = srcLineBuffer.baseAddress else { return -1 }
                    return dstLinesize.withUnsafeBufferPointer { dstLineBuffer -> Int32 in
                        guard let dstLineBase = dstLineBuffer.baseAddress else { return -1 }
                        return sws_scale(
                            swsContext,
                            srcBase,
                            srcLineBase,
                            0,
                            Int32(height),
                            dstBase,
                            dstLineBase
                        )
                    }
                }
            }
        }
        guard result >= 0 else { return }

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

    private func safeTearDownLocked() {
        if let codecContext = codecContext {
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

        videoStreamIndex = -1
        didLogVTReady = false
        didLogVTActive = false
        didLogSWActive = false

        DispatchQueue.main.async {
            self.currentFrame = nil
        }
    }
}

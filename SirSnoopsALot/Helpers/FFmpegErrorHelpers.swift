import Foundation

/// Cached FFmpeg error codes sourced from C helpers to avoid mismatches on Darwin platforms.
let FFmpegErrorEAGAIN: Int32 = fferr_eagain()
let FFmpegErrorEOF: Int32 = fferr_eof()

/// Mirrors the AVERROR macro so callers can convert POSIX errno values consistently.
@inline(__always)
func ffmpegMakeError(_ posixError: Int32) -> Int32 {
    return -posixError
}

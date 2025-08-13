#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/pixfmt.h>
#include <libavutil/hwcontext.h>

static enum AVPixelFormat ssa_get_hw_format(AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts) {
    const enum AVPixelFormat *p = pix_fmts;
    while (*p != AV_PIX_FMT_NONE) {
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX) {
            return *p;
        }
        p++;
    }
    // If VT not offered, fall back to the first software format in the list
    return pix_fmts[0];
}

int ssa_setup_videotoolbox(AVCodecContext *ctx) {
    AVBufferRef *hw_device_ctx = NULL;
    int err = av_hwdevice_ctx_create(&hw_device_ctx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL, NULL, 0);
    if (err < 0) {
        return err;
    }
    ctx->hw_device_ctx = av_buffer_ref(hw_device_ctx);
    av_buffer_unref(&hw_device_ctx);
    ctx->get_format = ssa_get_hw_format;
    return 0;
}


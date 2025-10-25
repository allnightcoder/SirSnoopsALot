#include "FFmpegBridge.h"
#include <libavutil/avutil.h>

static int ff_interrupt_cb_internal(void *opaque) {
    FFAbort *abortFlag = (FFAbort *)opaque;
    return (abortFlag && abortFlag->flag) ? 1 : 0;
}

void ff_install_interrupt_cb(AVFormatContext *fmt, FFAbort *abortFlag) {
    if (!fmt) {
        return;
    }
    fmt->interrupt_callback.callback = ff_interrupt_cb_internal;
    fmt->interrupt_callback.opaque = abortFlag;
}

int fferr_eagain(void) {
    return AVERROR(EAGAIN);
}

int fferr_eof(void) {
    return AVERROR_EOF;
}

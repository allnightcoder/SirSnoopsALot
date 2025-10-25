// FFmpegBridge.h
#ifndef FFmpegBridge_h
#define FFmpegBridge_h

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixfmt.h>
#include <libavutil/hwcontext.h>

typedef struct FFAbort {
    volatile int flag;
} FFAbort;

void ff_install_interrupt_cb(AVFormatContext *fmt, FFAbort *abortFlag);
int fferr_eagain(void);
int fferr_eof(void);

// Soft-enable VideoToolbox helpers (implemented in FFmpegHWAccel.c)
int ssa_setup_videotoolbox(AVCodecContext *ctx);

#endif /* FFmpegBridge_h */

#include <assert.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/pixfmt.h>
#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <caml/threads.h>
#include <caml/callback.h>

#include "avcodecidmapping.h"

struct Context {
  AVFormatContext*   fmtCtx;
  char*              filename;
};

static struct custom_operations context_ops = {
  "ffmpeg.Context",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

struct Context*
Context_val(value v)
{
  return (struct Context *) Data_custom_val(v);
}

enum StreamType {
  STREAM_VIDEO,
  STREAM_AUDIO
};

typedef struct StreamAux {
  enum StreamType    type;
  AVCodecContext*    codecCtx;
  AVStream*          avstream;
  struct SwsContext* swsCtx;
  struct SwrContext* swrCtx;
} StreamAux;

#define StreamAux_val(v) ((struct StreamAux *) Data_custom_val(v))

#define StreamSize              2
#define Stream_context_direct_val(v)   Field(v, 0)

struct Context*
Stream_context_val(value v)
{
  return Context_val(Stream_context_direct_val(v));
}

#define Stream_aux_direct_val(v) Field(v, 1)

struct StreamAux*
Stream_aux_val(value v)
{
  return StreamAux_val(Stream_aux_direct_val(v));
}

static struct custom_operations streamaux_ops = {
  "ffmpeg.StreamAux",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

#define Stream_val(v) ((struct Stream *) Data_custom_val(v))

static struct custom_operations avframe_ops = {
  "ffmpeg.AVFrame",
  custom_finalize_default,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

#define AVFrame_val(v) (*((struct AVFrame **) Data_custom_val(v)))

#define AVStream_val(v) (*((struct AVStream **) Data_custom_val(v)))

#define USER_PIXFORMAT AV_PIX_FMT_RGB32

static
value
wrap_ptr(struct custom_operations *custom, void* ptr)
{
  value v = alloc_custom(custom, sizeof(void*), 0, 1);
  * (void**) Data_custom_val(v) = ptr;
  return v;
}

enum Exception {
  ExnContextAlloc,
  ExnOpen,
  ExnFileIO,
  ExnStreamInfo,
  ExnWriteHeader,
  ExnMemory,
  ExnLogic,
  ExnEncode,
  ExnClosed,
  ExnCopyParameters
};

static
void
raise(enum Exception exn, int error)
{
  value args[2];
  args[0] = Val_int((int) exn);
  args[1] = Val_int(error);
  caml_raise_with_args(*caml_named_value("FFmpeg exception"), 2, args);
}

static
void
raise_if_not(int condition, enum Exception exn, int error)
{
  if (!condition) {
    raise(exn, error);
  }
}

static
void
raise_and_leave_blocking_section_if_not(int condition, enum Exception exn, int error)
{
  if (!condition) {
    caml_leave_blocking_section();
    raise(exn, error);
  }
}

static enum AVCodecID
avcodec_of_ocaml(value avcodec)
{
  return avcodecs[Int_val(avcodec)];
}

value
ffmpeg_create(value filename_)
{
  CAMLparam1(filename_);
  CAMLlocal1(ctx);

  av_register_all(); // this is fast to redo

  ctx = caml_alloc_custom(&context_ops, sizeof(struct Context), 0, 1);
  Context_val(ctx)->filename = strdup((char*) filename_);

  int ret;
  AVFormatContext* fmtCtx;
  caml_enter_blocking_section();
  ret = avformat_alloc_output_context2(&fmtCtx, NULL, NULL, (char*) filename_);
  caml_leave_blocking_section();
  raise_if_not(ret >= 0, ExnContextAlloc, ret);

  Context_val(ctx)->fmtCtx = fmtCtx;
  CAMLreturn(ctx);
}

value
ffmpeg_open_input(value filename_)
{
  CAMLparam1(filename_);
  CAMLlocal1(ctx);

  av_register_all(); // this is fast to redo

  ctx = caml_alloc_custom(&context_ops, sizeof(struct Context), 0, 1);
  Context_val(ctx)->filename = strdup((char*) filename_);

  int ret;
  AVFormatContext* fmtCtx;
  char* filename = Context_val(ctx)->filename;
  caml_enter_blocking_section();
  ret = avformat_open_input(&fmtCtx, filename, NULL, NULL);
  raise_and_leave_blocking_section_if_not(ret >= 0, ExnOpen, ret);

  ret = avformat_find_stream_info(fmtCtx, NULL);
  raise_and_leave_blocking_section_if_not(ret >= 0, ExnStreamInfo, ret);

  caml_leave_blocking_section();
  Context_val(ctx)->fmtCtx = fmtCtx;
  CAMLreturn(ctx);
}

value
ffmpeg_open(value ctx)
{
  CAMLparam1(ctx);
  int ret;
  char* filename = Context_val(ctx)->filename;
  AVFormatContext* fmtCtx = Context_val(ctx)->fmtCtx;

  caml_enter_blocking_section();
  if (!(fmtCtx->flags & AVFMT_NOFILE)) {
    ret = avio_open(&fmtCtx->pb, filename, AVIO_FLAG_WRITE);
    raise_and_leave_blocking_section_if_not(ret >= 0, ExnFileIO, ret);
  }

  ret = avformat_write_header(fmtCtx, NULL);
  caml_leave_blocking_section();
  raise_if_not(ret >= 0, ExnWriteHeader, ret);
  CAMLreturn(Val_unit);
}

value
ffmpeg_write_trailer(value ctx)
{
  CAMLparam1(ctx);

  if (Context_val(ctx)->fmtCtx) {
    AVFormatContext* fmtCtx = Context_val(ctx)->fmtCtx;
    caml_enter_blocking_section();
    if (fmtCtx->pb) {
      int ret = av_write_trailer(fmtCtx);
      raise_and_leave_blocking_section_if_not(ret == 0, ExnFileIO, ret);
    }
    caml_leave_blocking_section();
  }

  CAMLreturn(Val_unit);
}


value
ffmpeg_close(value ctx)
{
  CAMLparam1(ctx);

  if (Context_val(ctx)->fmtCtx) {
    AVFormatContext* fmtCtx = Context_val(ctx)->fmtCtx;
    caml_enter_blocking_section();
    //avcodec_close(Context_val(ctx)->avstream->codecpar); ??
    avformat_free_context(fmtCtx);

    if (!(fmtCtx->flags & AVFMT_NOFILE)) {
      int ret = avio_close(fmtCtx->pb);
      raise_and_leave_blocking_section_if_not(ret >= 0, ExnFileIO, ret);
    }

    caml_leave_blocking_section();
    Context_val(ctx)->fmtCtx = NULL;
    free(Context_val(ctx)->filename);
    Context_val(ctx)->filename = NULL;
  }
  
  CAMLreturn(Val_unit);
}

value
ffmpeg_stream_flush(value stream)
{
  CAMLparam1(stream);

  if (Stream_context_direct_val(stream) != Val_int(0) &&
      Stream_context_val(stream)->fmtCtx) {
    struct StreamAux streamAux = *Stream_aux_val(stream);
    caml_enter_blocking_section();
    AVPacket packet = { 0 };
    int ret = avcodec_send_frame(streamAux.codecCtx, NULL);
    raise_and_leave_blocking_section_if_not(ret >= 0, ExnEncode, ret);
    do {
      ret = avcodec_receive_packet(streamAux.codecCtx, &packet);
      if (ret == 0) {
        packet.stream_index = streamAux.avstream->index;
        ret = av_interleaved_write_frame(Stream_context_val(stream)->fmtCtx, &packet);
        raise_and_leave_blocking_section_if_not(ret >= 0, ExnFileIO, ret);
      }
    } while (ret == 0);
    //av_packet_free(&packet);
    caml_leave_blocking_section();
  }
  CAMLreturn(Val_unit);
}

value
ffmpeg_write(value stream, value rgbaFrame)
{
  CAMLparam2(stream, rgbaFrame);
  int ret;
  AVFrame* yuvFrame = av_frame_alloc();
  raise_if_not(!!yuvFrame, ExnMemory, 0);

  struct StreamAux streamAux = *Stream_aux_val(stream);
  AVFormatContext* fmtCtx = Stream_context_val(stream)->fmtCtx;

  yuvFrame->format = AV_PIX_FMT_YUV420P;
  yuvFrame->width = AVFrame_val(rgbaFrame)->width;
  yuvFrame->height = AVFrame_val(rgbaFrame)->height;

  ret = av_frame_get_buffer(yuvFrame, 32);
  raise_if_not(ret >= 0, ExnMemory, ret);

  ret = av_frame_make_writable(yuvFrame);
  raise_if_not(ret >= 0, ExnMemory, ret);

  yuvFrame->pts = AVFrame_val(rgbaFrame)->pts;

  caml_enter_blocking_section();

  sws_scale(streamAux.swsCtx,
            (const uint8_t * const *) AVFrame_val(rgbaFrame)->data,
            AVFrame_val(rgbaFrame)->linesize,
            0, streamAux.codecCtx->height, yuvFrame->data, yuvFrame->linesize);

  AVPacket packet = { 0 };
  av_init_packet(&packet);

  ret = avcodec_send_frame(streamAux.codecCtx, yuvFrame);
  raise_and_leave_blocking_section_if_not(ret == 0, ExnEncode, ret);

  ret = avcodec_receive_packet(streamAux.codecCtx, &packet);
  raise_and_leave_blocking_section_if_not(ret == 0 || ret == AVERROR(EAGAIN), ExnEncode, ret);
  if (ret == 0) {
    packet.stream_index = streamAux.avstream->index;
    ret = av_interleaved_write_frame(fmtCtx, &packet);
    raise_and_leave_blocking_section_if_not(ret >= 0, ExnFileIO, ret);
  }

  av_frame_free(&yuvFrame);
  //av_packet_free(&packet);

  caml_leave_blocking_section();

  CAMLreturn(Val_unit);
}

value
ffmpeg_stream_new_video(value ctx, value av_codec_id, value video_info_)
{
  CAMLparam3(ctx, av_codec_id, video_info_);
  CAMLlocal1(stream);

  stream = caml_alloc_tuple(StreamSize);
  enum AVCodecID codec_id = avcodec_of_ocaml(av_codec_id);
  AVCodec* codec = avcodec_find_encoder(codec_id);
  AVCodecContext* codecCtx = avcodec_alloc_context3(codec);
  int ret;

  Stream_aux_direct_val(stream) = caml_alloc_custom(&streamaux_ops, sizeof(struct StreamAux), 0, 1);
  StreamAux* streamAux = Stream_aux_val(stream);
  streamAux->type = Val_int(STREAM_VIDEO);
  Stream_context_direct_val(stream) = ctx;
  streamAux->codecCtx = codecCtx;
  streamAux->avstream = avformat_new_stream(Context_val(ctx)->fmtCtx, NULL);

  streamAux->avstream->id = 0;

  AVCodecParameters* codecpar = streamAux->avstream->codecpar;
  ret = avcodec_parameters_from_context(streamAux->avstream->codecpar, codecCtx);
  raise_if_not(ret >= 0, ExnCopyParameters, ret);

  codecpar->codec_id = codec_id;
  /* streamAux->avstream->codecpar->rc_min_rate = 50000; */
  /* streamAux->avstream->codecpar->rc_max_rate = 200000; */
  /* streamAux->avstream->codecpar->bit_rate = 10000; */
  codecpar->width    = Int_val(Field(video_info_, 0));
  codecpar->height   = Int_val(Field(video_info_, 1));
  codecpar->format   = AV_PIX_FMT_YUV420P;
  codecpar->bit_rate = 500000;
  //streamAux->avstream->codecpar->gop_size = 30;

  if (Context_val(ctx)->fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
    streamAux->codecCtx->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;
  }

  streamAux->codecCtx->time_base = (AVRational) {1, 10000};
  streamAux->avstream->time_base = (AVRational) {1, 10000};

  codecCtx->gop_size = 12;

  ret = avcodec_parameters_to_context(codecCtx, streamAux->avstream->codecpar);
  raise_if_not(ret >= 0, ExnCopyParameters, ret);
  
  AVDictionary* codecOpts = NULL;
  /* av_dict_set(&codecOpts, "profile", "baseline", 0); */
  /* av_dict_set(&codecOpts, "crf", "3", 0); */
  /* av_dict_set(&codecOpts, "vbr", "1", 0); */
  //av_dict_set(&codecOpts, "x264-params", "bitrate=2", 0);
  //av_dict_set(&codecOpts, "x264-params", "crf=40:keyint=60:vbv_bufsize=40000:vbv_maxrate=150000", 0);
  /* av_dict_set(&codecOpts, "x264-params", "crf=36:keyint=60", 0); */

  caml_enter_blocking_section();
  ret = avcodec_open2(codecCtx, codec, &codecOpts);
  raise_and_leave_blocking_section_if_not(ret >= 0, ExnOpen, ret);
  caml_leave_blocking_section();

  assert(codecCtx->pix_fmt == AV_PIX_FMT_YUV420P);

  ret = avcodec_parameters_from_context(streamAux->avstream->codecpar, codecCtx);
  raise_if_not(ret >= 0, ExnCopyParameters, ret);

  streamAux->swsCtx =
    sws_getContext(streamAux->codecCtx->width, streamAux->codecCtx->height, USER_PIXFORMAT,
                   streamAux->codecCtx->width, streamAux->codecCtx->height, streamAux->codecCtx->pix_fmt,
                   0, NULL, NULL, NULL);
  
  CAMLreturn((value) stream);
}

value
ffmpeg_stream_new_audio(value ctx, value av_codec_id, value audio_info_)
{
  CAMLparam3(ctx, av_codec_id, audio_info_);
  CAMLlocal1(stream);
  enum AVCodecID codec_id = avcodec_of_ocaml(av_codec_id);
  AVCodec* codec = avcodec_find_encoder(codec_id);
  AVCodecContext* codecCtx = avcodec_alloc_context3(codec);
  int ret;

  stream = caml_alloc_tuple(StreamSize);

  Stream_aux_direct_val(stream) = caml_alloc_custom(&streamaux_ops, sizeof(struct StreamAux), 0, 1);
  StreamAux* streamAux = Stream_aux_val(stream);
  streamAux->type = Val_int(STREAM_AUDIO);
  Stream_context_direct_val(stream) = ctx;
  streamAux->codecCtx = codecCtx;
  streamAux->avstream = avformat_new_stream(Context_val(ctx)->fmtCtx, codec);

  AVCodecParameters* codecpar = streamAux->avstream->codecpar;
  ret = avcodec_parameters_from_context(streamAux->avstream->codecpar, codecCtx);
  raise_if_not(ret >= 0, ExnCopyParameters, ret);
  codecpar->codec_id    = codec_id;
  codecpar->sample_rate = Int_val(Field(audio_info_, 0));
  codecpar->channels    = Int_val(Field(audio_info_, 1));
  codecpar->format      = codec->sample_fmts ? codec->sample_fmts[0] : AV_SAMPLE_FMT_FLTP;
  codecpar->channel_layout = AV_CH_LAYOUT_STEREO;
  //streamAux->avstream->codecpar->channels    = av_get_channel_layout_nb_channels(streamAux->avstream->codecpar->channel_layout);

  if (Context_val(ctx)->fmtCtx->oformat->flags & AVFMT_GLOBALHEADER) {
    streamAux->codecCtx->flags   |= AV_CODEC_FLAG_GLOBAL_HEADER;
  }

  streamAux->codecCtx->time_base = (AVRational) {1, 10000};
  streamAux->avstream->time_base = (AVRational) {1, 10000};

  ret = avcodec_parameters_to_context(codecCtx, streamAux->avstream->codecpar);
  raise_if_not(ret >= 0, ExnCopyParameters, ret);
  
  AVDictionary* codecOpts = NULL;

  caml_enter_blocking_section();
  ret = avcodec_open2(codecCtx, codec, &codecOpts);
  raise_and_leave_blocking_section_if_not(ret >= 0, ExnOpen, ret);
  caml_leave_blocking_section();

  if (streamAux->codecCtx->sample_fmt != AV_SAMPLE_FMT_S16) {
    streamAux->swrCtx = swr_alloc();
    assert(streamAux->swrCtx);

    av_opt_set_int       (streamAux->swrCtx, "in_channel_count",   streamAux->avstream->codecpar->channels, 0);
    av_opt_set_int       (streamAux->swrCtx, "in_sample_rate",     streamAux->avstream->codecpar->sample_rate, 0);
    av_opt_set_sample_fmt(streamAux->swrCtx, "in_sample_fmt",      AV_SAMPLE_FMT_S16, 0);
    av_opt_set_int       (streamAux->swrCtx, "out_channel_count",  streamAux->avstream->codecpar->channels, 0);
    av_opt_set_int       (streamAux->swrCtx, "out_sample_rate",    streamAux->avstream->codecpar->sample_rate, 0);
    av_opt_set_sample_fmt(streamAux->swrCtx, "out_sample_fmt",     streamAux->codecCtx->sample_fmt, 0);
  }
  

  CAMLreturn((value) stream);
}

value
ffmpeg_stream_new(value ctx, value av_codec_id, value media_kind_)
{
  CAMLparam3(ctx, av_codec_id, media_kind_);
  CAMLlocal1(ret);

  if (Context_val(ctx)->fmtCtx) {
    switch (Tag_val(media_kind_)) {
    case 0: {
      ret = ffmpeg_stream_new_video(ctx, av_codec_id, Field(media_kind_, 0));
    } break;
    case 1: {
      ret = ffmpeg_stream_new_audio(ctx, av_codec_id, Field(media_kind_, 0));
    } break;
    }
  } else {
    raise(ExnClosed, 0);
  }
  
  CAMLreturn(ret);
}

value
ffmpeg_stream_close(value stream)
{
  CAMLparam1(stream);

  if (Stream_context_direct_val(stream) != Val_int(0)) {
    // can this be called?!
    avcodec_close(Stream_aux_val(stream)->codecCtx);
    if (Stream_aux_val(stream)->swsCtx) {
      sws_freeContext(Stream_aux_val(stream)->swsCtx);
    }
    Stream_context_direct_val(stream) = Val_int(0);
 } else {
    raise(ExnClosed, 0);
  }

  CAMLreturn(Val_unit);
}

value
ffmpeg_frame_new(value stream, value pts_)
{
  CAMLparam2(stream, pts_);
  CAMLlocal1(frame);
  if (Stream_context_direct_val(stream) != Val_int(0)) {
    double pts = Double_val(pts_);
    frame = wrap_ptr(&avframe_ops, av_frame_alloc());
    AVFrame_val(frame)->format = USER_PIXFORMAT; // 0xrrggbbaa
    AVFrame_val(frame)->width = Stream_aux_val(stream)->codecCtx->width;
    AVFrame_val(frame)->height = Stream_aux_val(stream)->codecCtx->height;

    int ret;
    ret = av_frame_get_buffer(AVFrame_val(frame), 32);
    raise_if_not(ret >= 0, ExnMemory, ret);

    ret = av_frame_make_writable(AVFrame_val(frame));
    raise_if_not(ret >= 0, ExnLogic, ret);

    AVFrame_val(frame)->pts = pts = (int64_t) (Stream_aux_val(stream)->codecCtx->time_base.den * pts);
  } else {
    raise(ExnClosed, 0);
  }

  CAMLreturn((value) frame);
}

value
ffmpeg_frame_buffer(value frame)
{
  CAMLparam1(frame);
  CAMLreturn(caml_ba_alloc_dims(CAML_BA_INT32, 1,
                                AVFrame_val(frame)->data[0],
                                AVFrame_val(frame)->linesize[0] * AVFrame_val(frame)->height));
}

value
ffmpeg_frame_free(value frame)
{
  CAMLparam1(frame);
  AVFrame *ptr = AVFrame_val(frame);
  av_frame_free(&ptr);
  AVFrame_val(frame) = NULL;
  CAMLreturn(Val_unit);
}

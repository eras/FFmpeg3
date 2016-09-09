type 'rw context = 'rw FFmpegTypes.context
type pts = float
type width = int
type height = int
type 'media_info frame = 'media_info FFmpegTypes.frame
type video = FFmpegTypes.video = { v_width : int; v_height : int; }
type audio =
  FFmpegTypes.audio = {
  a_samplerate : int;
  a_channels : int;
  a_layout : int option;
}
type data = FFmpegTypes.data
type 'a media_new_info =
  'a FFmpegTypes.media_new_info =
    CreateVideo : video -> [ `Video ] media_new_info
  | CreateAudio : audio -> [ `Audio ] media_new_info
  | CreateData : data -> [ `Data ] media_new_info
type 'a media_type =
  'a FFmpegTypes.media_type =
    Video : [ `Video ] media_type
  | Audio : [ `Audio ] media_type
  | Data : [ `Data ] media_type
type 'rw rw = 'rw constraint 'rw = [< `Read | `Write ]
type ('media_info, 'a) stream = ('media_info, 'a) FFmpegTypes.stream
  constraint 'a = [< `Read | `Write ]
type 'format bitmap =
    (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
type avmedia_type =
  FFmpegTypes.avmedia_type =
    AVMEDIA_TYPE_UNKNOWN
  | AVMEDIA_TYPE_VIDEO
  | AVMEDIA_TYPE_AUDIO
  | AVMEDIA_TYPE_DATA
  | AVMEDIA_TYPE_SUBTITLE
  | AVMEDIA_TYPE_ATTACHMENT
val read : [> `Read ]
type index = int
type ffmpeg_exception =
  FFmpegTypes.ffmpeg_exception =
    ContextAlloc
  | Open
  | FileIO
  | StreamInfo
  | WriteHeader
  | Memory
  | Logic
  | Encode
  | Closed
exception Exception of ffmpeg_exception * int
module FFmpegCTypes :
  sig
    val avmedia_type_unknown : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_video : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_audio : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_data : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_subtitle : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_attachment : int64 FFmpegGeneratedCTypes.const
    val avmedia_type_to_c :
      FFmpegTypes.avmedia_type -> int64 FFmpegGeneratedCTypes.const
    val avmedia_type_of_c :
      int64 FFmpegGeneratedCTypes.const -> FFmpegTypes.avmedia_type
  end
val create : string -> [ `Write ] context
val open_input : string -> [ `Read ] context
external new_stream :
  [ `Write ] context ->
  'media_info media_new_info -> ('media_info, [< `Write ]) stream
  = "ffmpeg_stream_new"
external open_ : 'rw context -> unit = "ffmpeg_open"
external new_frame :
  ('media_info, [ `Write ]) stream -> pts -> 'media_info frame
  = "ffmpeg_frame_new"
external frame_buffer : [> `Video ] frame -> 'format bitmap
  = "ffmpeg_frame_buffer"
external free_frame : 'media_info frame -> unit = "ffmpeg_frame_free"
external write :
  ('media_info, [< `Read | `Write ]) stream -> 'media_info frame -> unit
  = "ffmpeg_write"
external close_stream : ('media_info, [< `Read | `Write ]) stream -> unit
  = "ffmpeg_stream_close"
external close : 'rw context -> unit = "ffmpeg_close"

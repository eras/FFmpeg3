open Batteries

include FFmpeg3Avcodecs

include FFmpegTypes

let _ = Callback.register_exception "FFmpeg exception" (Exception (ContextAlloc, 0))

module FFmpegCTypes = FFmpegBindings.Types(FFmpegGeneratedCTypes)

let _ = FFmpegCTypes.avmedia_type_to_c AVMEDIA_TYPE_VIDEO

let _ = Printexc.register_printer @@ fun exn ->
  match exn with
  | Exception (kind, code) ->
    let kind_str = match kind with
      | ContextAlloc -> "ContextAlloc"
      | Open -> "Open"
      | FileIO -> "FileIO"
      | StreamInfo -> "StreamInfo"
      | WriteHeader -> "WriteHeader"
      | Memory -> "Memory"
      | Logic -> "Logic"
      | Encode -> "Encode"
      | Closed -> "Closed"
      | CopyParameters -> "CopyParameters"
    in
    Some (Printf.sprintf "FFmpeg.Exception (%s, %d)" kind_str code)
  | _ -> None

module LowLevel = struct
  type 'rw context
  type ('media_info, 'a) stream constraint 'a = [< `Read | `Write ]
  type 'media_info packet
  type ('media_info, 'access) codec_context constraint 'access = [< `Read | `Write ]

  external create_ : string -> [`Write] context = "ffmpeg_create"

  (* Wrapper ensuring the file gets evaluated if the functionality is used *)
  let create x = create_ x

  external open_input_ : string -> [`Read] context = "ffmpeg_open_input"

  (* Wrapper ensuring the file gets evaluated if the functionality is used *)
  let open_input x = open_input_ x

  external new_stream : [`Write] context -> av_codec_id -> 'media_info media_new_info -> ('media_info, [<`Write]) stream = "ffmpeg_stream_new"

  (* external open_stream : [`Read] context -> index -> 'media_info media_type -> ('media_info, [<`Write]) stream = "ffmpeg_stream_open" *)

  external open_ : 'rw context -> unit = "ffmpeg_open"

  external make_frame_for : ('media_info, [`Write]) stream -> pts -> 'media_info frame = "ffmpeg_make_frame_for"

  external make_frame : video_frame_info -> [> `Video] frame = "ffmpeg_make_frame"

  external frame_buffer : [>`Video] frame -> 'format bitmap = "ffmpeg_frame_buffer"

  external free_frame : 'media_info frame -> unit = "ffmpeg_frame_free"

  external write : ('media_info, 'rw) stream -> 'media_info frame -> unit = "ffmpeg_write"

  external close_stream : ('media_info, 'rw) stream -> unit = "ffmpeg_stream_close"

  external write_trailer : 'rw context -> unit = "ffmpeg_write_trailer"

  external flush : ('media_info, [< `Write ]) stream -> unit = "ffmpeg_stream_flush"

  external close : 'rw context -> unit = "ffmpeg_close"

  external send_frame : ('media_info, [<`Write]) codec_context -> 'media_info frame option -> unit = "ffmpeg_send_frame"

  external receive_packet : ('media_info, [<`Write]) codec_context -> 'media_info packet = "ffmpeg_receive_packet"

  external write_packet_interleaved : ('media_info, [<`Write]) stream -> 'media_info packet = "ffmpeg_write_packet_interleaved"

  external get_stream_codec_context : ('media_info, _) stream -> ('media_info, _) codec_context  = "ffmpeg_get_stream_codec_context"

  module Sws = struct
    type t
    external make : src : (width * height * av_pixel_format) -> dst : (width * height * av_pixel_format) -> t = "ffmpeg_sws_make"
    external scale : t -> src:'media_info_in frame -> dst:'media_info_out frame -> unit = "ffmpeg_sws_scale"
  end
end

type ('media_info, 'rw) stream = {
  s_id     : int;
  s_stream : ('media_info, 'rw) LowLevel.stream;
} constraint 'a = [< `Read | `Write ]

type 'rw stream_holder = Stream : { stream : ('media_info, 'rw) stream } -> 'rw stream_holder

type 'rw context = {
  c_lowlevel         : 'rw LowLevel.context;
  mutable c_streams  : 'rw stream_holder list;
  c_opened           : bool;
}

let create filename = {
  c_lowlevel = LowLevel.create filename;
  c_streams = [];
  c_opened = false;
}

let open_input_ filename = {
  c_lowlevel = LowLevel.open_input_ filename;
  c_streams = [];
  c_opened = false;
}

let new_id () = Oo.id (object end)

let close_streams context =
  flip List.iter context.c_streams @@ function
    Stream { stream } ->
    LowLevel.close_stream stream.s_stream

let flush_streams context =
  flip List.iter context.c_streams @@ function
    Stream { stream } ->
    LowLevel.flush stream.s_stream

let new_stream : [`Write] context -> av_codec_id -> 'media_info media_new_info -> ('media_info, [<`Write]) stream =
  fun context av_codec_id media_new_info ->
    let ll_stream = LowLevel.new_stream context.c_lowlevel av_codec_id media_new_info in
    let stream = { s_id = new_id ();
                   s_stream = ll_stream } in
    context.c_streams <- Stream { stream }::context.c_streams;
    stream

let open_ : 'rw context -> unit =
  fun context ->
    LowLevel.open_ context.c_lowlevel

let new_frame : ('media_info, [`Write]) stream -> pts -> 'media_info frame =
  fun stream pts ->
    LowLevel.make_frame_for stream.s_stream pts

let frame_buffer : [>`Video] frame -> 'format bitmap =
  fun frame ->
    LowLevel.frame_buffer frame

let free_frame : 'media_info frame -> unit =
  fun frame ->
    LowLevel.free_frame frame

let write : ('media_info, 'rw) stream -> 'media_info frame -> unit =
  fun stream frame ->
    LowLevel.write stream.s_stream frame

let close_stream : ('media_info, 'rw) stream -> unit =
  fun stream ->
    LowLevel.close_stream stream.s_stream

let write_trailer : 'rw context -> unit =
  fun context ->
    LowLevel.write_trailer context.c_lowlevel

let flush : ('media_info, [< `Write ]) stream -> unit =
  fun stream ->
    LowLevel.flush stream.s_stream

let close : 'rw context -> unit =
  fun context ->
    LowLevel.close context.c_lowlevel

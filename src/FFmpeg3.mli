(* FFmpeg3 bindings for OCaml *)

(*
 * The MIT License (MIT)
 *
 * Copyright (c) 2016 Erkki Seppälä
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *)

include module type of FFmpeg3Avcodecs

type 'rw context

type pts = float                (** Presentation time *)

type width = int                (** Width of a bitmap in pixels *)

type height = int               (** Height of a bitmap in pixels *)

type 'media_info frame = 'media_info FFmpegTypes.frame

type video = FFmpegTypes.video = {
  v_width : width;              (** Video width *)
  v_height : height;            (** Video height *)
}

type audio = FFmpegTypes.audio = {
  a_samplerate : int;           (** Sample rate of the audio *)
  a_channels : int;             (** Number of channels in the audio *)
  a_layout : int option;        (** Channel layout *)
}

type video_frame_info = FFmpegTypes.video_frame_info = {
  fi_width : width;
  fi_height : height;
  fi_pixfmt : FFmpeg3Avcodecs.av_pixel_format;
}

type data = FFmpegTypes.data    (** Raw data *)

type 'a media_new_info = 'a FFmpegTypes.media_new_info =
  | CreateVideo : video -> [ `Video ] media_new_info
  | CreateAudio : audio -> [ `Audio ] media_new_info
  | CreateData  : data -> [ `Data ] media_new_info

type 'a media_type = 'a FFmpegTypes.media_type =
  | Video : [ `Video ] media_type
  | Audio : [ `Audio ] media_type
  | Data  : [ `Data ] media_type

type 'rw rw = 'rw constraint 'rw = [< `Read | `Write ]

(** A media stream (typically a track) *)
type ('media_info, 'a) stream constraint 'a = [< `Read | `Write ]

(** Raw bitmap *)
type 'format bitmap = (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

type avmedia_type = FFmpegTypes.avmedia_type =
  | AVMEDIA_TYPE_UNKNOWN        (** Unkown media type; typically error  *)
  | AVMEDIA_TYPE_VIDEO          (** Video media *)
  | AVMEDIA_TYPE_AUDIO          (** Audio media *)
  | AVMEDIA_TYPE_DATA           (** Timed data *)
  | AVMEDIA_TYPE_SUBTITLE       (** Subtitle *)
  | AVMEDIA_TYPE_ATTACHMENT     (** Attachment *)

val read : [> `Read ]

type ffmpeg_exception = FFmpegTypes.ffmpeg_exception =
  | ContextAlloc                (** Error allocating a context *)
  | Open                        (** Error while opening a file *)
  | FileIO                      (** File IO error *)
  | StreamInfo                  (** Error while retrieving stream info *)
  | WriteHeader                 (** Error while writing header *)
  | Memory                      (** Memory allocatino error *)
  | Logic                       (** Logic error (bug) *)
  | Encode                      (** Error while encoding *)
  | Closed                      (** The object was closed before current access *)
  | CopyParameters              (** Failed to copy codec parameters from context *)

exception Exception of ffmpeg_exception * int

module LowLevel : sig
  type 'rw context
  type ('media_info, 'a) stream constraint 'a = [< `Read | `Write ]

  (** [create filename] creates a new media file *)
  val create : string -> [ `Write ] context

  (** [open_input filename] opens an existing media file *)
  val open_input : string -> [ `Read ] context

  (** [new_stream context media_info] creates a new stream for a
      [create]d media file context *)
  external new_stream :
    [ `Write ] context ->
    av_codec_id -> 'media_info media_new_info -> ('media_info, [< `Write ]) stream
    = "ffmpeg_stream_new"

  (** [open_ ctx] finished opening a file for writing *)
  external open_ : 'rw context -> unit = "ffmpeg_open"

  (** [write_trailer ctx] writes the trailer. Do this before close_stream! *)
  external write_trailer : 'rw context -> unit = "ffmpeg_write_trailer"

  (** [close ctx] closes a media file  *)
  external close : 'rw context -> unit = "ffmpeg_close"

  (** [new_frame_for pts] creates a new video frame with given time stamp *)
  external make_frame_for :
    ('media_info, [ `Write ]) stream -> pts -> 'media_info frame
    = "ffmpeg_make_frame_for"

  (** [new_frame_for pts] creates a new video frame with given time stamp *)
  external make_frame : video_frame_info -> 'media_info frame = "ffmpeg_make_frame"

  (** [close_stream stream] closes a stream withni a media file context *)
  external close_stream : ('media_info, [< `Read | `Write ]) stream -> unit
    = "ffmpeg_stream_close"

  (** [free_frame frame] releases a frame *)
  external free_frame : 'media_info frame -> unit = "ffmpeg_frame_free"

  (** [write stream frame] writes a frame to a stream *)
  external write :
    ('media_info, [< `Read | `Write ]) stream -> 'media_info frame -> unit
    = "ffmpeg_write"

  external flush : ('media_info, [< `Write ]) stream -> unit = "ffmpeg_stream_flush"

  (* todo *)
  external frame_buffer : [> `Video ] frame -> 'format bitmap
    = "ffmpeg_frame_buffer"
end

(** [create filename] creates a new media file *)
val create : string -> [ `Write ] context

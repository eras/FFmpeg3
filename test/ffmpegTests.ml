open OUnit2

module F = struct
  include FFmpeg3
  module LL = LowLevel
end

let create_close test_ctx =
  let f = F.LL.create "create_close.mp4" in
  F.LL.close f;
  ()

let new_stream test_ctx =
  let f = F.LL.create "new_stream.mp4" in
  let s = F.LL.new_stream f AV_CODEC_ID_H264 (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.LL.close_stream s;
  F.LL.close f;
  ()

let write_frame test_ctx =
  let f = F.LL.create "write_frame.mp4" in
  let s = F.LL.new_stream f AV_CODEC_ID_H264 (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.LL.open_ f;
  let frame = F.LL.make_frame_for s 0.0 in
  let _fb = F.LL.frame_buffer frame in
  F.LL.write s frame;
  F.LL.free_frame frame;
  F.LL.close_stream s;
  F.LL.close f;
  ()

let write_frames test_ctx =
  let f = F.LL.create "write_frames.mp4" in
  let s = F.LL.new_stream f AV_CODEC_ID_H264 (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.LL.open_ f;
  for i = 0 to 100 do
    let frame = F.LL.make_frame_for s (float i /. 10.0) in
    let _fb = F.LL.frame_buffer frame in
    F.LL.write s frame;
    F.LL.free_frame frame;
  done;
  F.LL.close_stream s;
  F.LL.close f;
  ()

let close_stream_twice test_ctx =
  let f = F.LL.create "new_stream.mp4" in
  let s = F.LL.new_stream f AV_CODEC_ID_H264 (F.CreateVideo { F.v_width = 128; v_height = 128 }) in
  F.LL.close_stream s;
  assert_raises (F.Exception (Closed, 0)) (fun () ->
      F.LL.close_stream s;
    );
  F.LL.close f;
  ()

let ffmpeg =
  "FFmpeg" >:::
  ["create_close"       >:: create_close;
   "new_stream"         >:: new_stream;
   "write_frame"        >:: write_frame;
   "write_frames"       >:: write_frames;
   "close_stream_twice" >:: close_stream_twice;
   ]

let _ =
  run_test_tt_main ffmpeg
    

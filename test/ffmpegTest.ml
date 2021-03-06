open Batteries
open FFmpeg3

let main () =
  let ctx = create "foo.mp4" in
  let stream = new_stream ctx AV_CODEC_ID_H264 (CreateVideo { v_width = 640; v_height = 480 }) in
  let (_ : unit) = open_ ctx in
  let _ = List.(0 -- 200) |> Enum.iter (
    fun n ->
      let frame = new_frame stream (float n) in
      let frame_buf = frame_buffer frame in
      let width = 640 in
      let fillbox x0 y0 x1 y1 color =
        for y = y0 to y1 do
          for x = x0 to x1 do
            frame_buf.{y * width + x} <- color
          done
        done
      in
      fillbox 0 0 (640 - 1) (480 - 1) 0l;
      fillbox (n + 100) (100) (n + 200) (200) 0xffffffl;
      write stream frame;
      free_frame frame;
      ()
    ) in
  flush stream;
  write_trailer ctx;
  close_stream stream;
  close ctx;
  ()

let _ = main ()

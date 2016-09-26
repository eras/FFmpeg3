open Batteries

let defer at_scope_exit k =
  let v = wrap k () in
  at_scope_exit ();
  ok v

let temp_file_with contents k =
  let (name, channel) = Filename.open_temp_file "dumpAvcodecs" ".c" in
  defer
    (fun () -> Sys.remove name)
    (fun () ->
       Pervasives.output_string channel contents; 
       Pervasives.close_out channel;
       k name
    )

let get_list include_file pattern =
  temp_file_with ("#include <" ^ include_file ^ ">\n") @@
  (fun source_file_name ->
     let command =
       Printf.sprintf
         ({|cpp $(pkg-config --cflags libavcodec) "%s" |
            sed 's/^\s\s*\(%s[A-Z0-9_]*\).*/\1/; t; d'|})
         source_file_name
         pattern
     in
     let input = Unix.open_process_in command in
     defer
       (fun () -> close_in input)
       (fun () ->
          IO.lines_of input |> List.of_enum
       )
  )

let get_avcodecs_list () = get_list "libavcodec/avcodec.h" "AV_CODEC_ID_"

let ml_define_variants codecs =
  let variants = flip List.map codecs @@ fun codec -> Printf.sprintf "| %s" codec in
  "type av_codec_id =\n" ^
  String.concat "\n" variants ^
  "\n"

let c_define_mapping codecs =
  let count = List.length codecs in
  Printf.sprintf "enum AVCodecID avcodecs[%d] = {\n" count ^
  String.concat ",\n" codecs ^
  "};\n"

let map_from_codec_variant_code codec =
  "value map_from_" ^ codec ^ "(value void) { return Int_val(" ^ codec ^ "); }\n"

let main () =
  let mode = ref `None in
  let set_mode mode_ () =
    match !mode with
    | `None -> mode := mode_
    | _ -> mode := `Twice
  in
  let output_file = ref None in
  let spec = Arg.[
        ("-c", Unit (set_mode `GenerateC), "Generate C code");
        ("-ml", Unit (set_mode `GenerateML), "Generate OCaml code");
        ("-out", String (fun x -> output_file := Some x), "Set output file");
    ] in
  let codecs = lazy (get_avcodecs_list ()) in
  Arg.parse spec (fun _ -> assert false) "usage: dumpAvcodecs [mode]";
  match !output_file with
  | None ->
    Printf.printf "Need to set output file with -out\n%!";
  | Some output_file ->
    File.with_file_out output_file @@ fun file ->
    match !mode with
    | `None -> Printf.printf "Mode not set\n%!"
    | `Twice -> Printf.printf "Cannot set mode twice\n%!"
    | `GenerateML -> Printf.fprintf file "%s\n" (ml_define_variants (Lazy.force codecs))
    | `GenerateC -> Printf.fprintf file "%s" (c_define_mapping (Lazy.force codecs))

let _ = main ()
    

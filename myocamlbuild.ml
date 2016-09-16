open Ocamlbuild_plugin
open Command
open Unix

let hardcoded_version_file = ".version"
let version_file = "src/version.ml"
let version_content () =
  let version_from_git () =
    let i = open_process_in "git describe --dirty --always --tags" in
    let l = input_line i in
    if close_process_in i = WEXITED 0 then l
    else raise Not_found in
  let hardcoded_version () =
    let i = open_in hardcoded_version_file in
    let s = input_line i in
    close_in i; s in
  let version =
    try hardcoded_version () with _ ->
      try version_from_git () with _ ->
        failwith "Unable to determine version" in
  "let version = \"" ^ version ^ "\"\n"

let rpathify option =
  if String.length option > 2 && String.sub option 0 2 = "-L"; then
    A("-Wl,-rpath," ^ String.sub option 2 (String.length option - 2))
  else
    A option

(* Copied from https://github.com/dbuenzli/tgls/blob/master/myocamlbuild.ml *)
let pkg_config flags package =
  let has_package =
    try ignore (run_and_read ("pkg-config --exists " ^ package)); true
    with Failure _ -> false
  in
  let cmd tmp =
    Command.execute ~quiet:true &
      Cmd( S [ A "pkg-config"; A ("--" ^ flags); A package; Sh ">"; A tmp]);
    List.map rpathify (string_list_of_file tmp)
  in
  if has_package then with_temp_file "pkgconfig" "pkg-config" cmd else []

let ctypes = Findlib.query "ctypes"

let ffmpeg_packages = "libavcodec,libavformat,libswscale,libswresample,libavutil"
let ffmpeg_flags = lazy (pkg_config "cflags" ffmpeg_packages)
let ffmpeg_libs = lazy (pkg_config "libs" ffmpeg_packages)

let prefixify prefix flags = flags |> List.map (fun x -> [A prefix; x]) |> List.concat

let ccoptify = prefixify "-ccopt"
let cclibify = prefixify "-cclib"
let dllibify = prefixify "-dllib"

let ctypes_rules cbase phase1gen phase2gen ocaml =
  rule "ctypes generated c"
    ~dep:phase1gen
    ~prod:(cbase ^ ".c")
    (fun _ _ ->
       Cmd(S[P ("./" ^ phase1gen); Sh">"; A(cbase ^ ".c")]));

  rule "ctypes generated exe"
    ~dep:(cbase ^ ".o")
    ~prod:phase2gen
    (fun _ _ ->
       Cmd (S ([Sh "cc"; A(cbase ^ ".o");
                A"-o"; A phase2gen;
                A"-I"; A ctypes.Findlib.location] @ Lazy.force ffmpeg_libs))
    );

  rule "ctypes generated ml"
    ~dep:phase2gen
    ~prod:ocaml
    (fun _ _ ->
       Cmd(S[P ("./" ^ phase2gen); Sh">"; A ocaml]))

let avcodecs_module = "src/FFmpeg3Avcodecs"
let avcodecs_module_ml = avcodecs_module ^ ".ml"
let avcodec_idmapping_h = "src/avcodecidmapping.h"

let cmi x = x ^ ".cmi"
let cmo x = x ^ ".cmo"
let cmx x = x ^ ".cmx"

let setup_dumpAvcodecs () =
  let binary = "src/dumpAvcodecs.byte" in

  rule "dumpAvcodecs tool"
    ~dep:binary
    ~prod:avcodecs_module_ml
    (fun _ _ ->
       Cmd(S[P binary;
             A"-ml";
             A"-out"; A avcodecs_module_ml;
            ]
          )
    );

  rule "dumpAvcodecs id mapping"
    ~dep:binary
    ~prod:avcodec_idmapping_h
    (fun _ _ ->
       Cmd(S[P binary;
             A"-c";
             A"-out"; A avcodec_idmapping_h;
            ]
          )
    )

let setup_ffmpeg () =
  setup_dumpAvcodecs ();
  dep ["compile"; "build_FFmpeg"; "c"] [avcodec_idmapping_h];
  dep ["compile"; "build_FFmpeg"; "ocaml"] [avcodecs_module |> cmi];
  dep ["link"; "build_FFmpeg"; "ocaml"; "byte"] [avcodecs_module |> cmo];
  dep ["link"; "build_FFmpeg"; "ocaml"; "native"] [avcodecs_module |> cmx];

  flag ["mktop"; "use_libFFmpeg"] (A"-custom");
  flag ["link"; "byte"; "use_libFFmpeg"] (A"-custom");

  flag ["c"; "compile"; "build_FFmpeg"] (S [
      (S (ccoptify @@ Lazy.force ffmpeg_flags));
      (S [A "-ccopt"; A "-O0"]);
      (S [A "-ccopt"; A "-W"]);
      (S [A "-ccopt"; A "-Wall"]);
      (S [A "-ccopt"; A "-Wno-missing-field-initializers"])
    ]);
  flag ["link"; "library"; "ocaml"; "build_FFmpeg"; "native"] (S[
      S (cclibify @@ Lazy.force ffmpeg_libs);
    ]
    );
  flag ["ocamlmklib"] (S[
      S (Lazy.force ffmpeg_libs);
    ]
    );
  flag ["link"; "library"; "ocaml"; "build_FFmpeg"; "byte"] (S[
      S [A "-dllib"; A"-lFFmpeg-stubs"];
    ]);
  flag ["link"; "ocaml"; "use_FFmpeg"; "byte"] (S[
      S [A "-dllib"; A"-lFFmpeg-stubs"];
    ]);
  flag ["link"; "library"; "ocaml"; "build_FFmpeg"; "native"] (S[
      S [A "-cclib"; A"-lFFmpeg-stubs"];
    ]);
  dep ["link"; "build_FFmpeg"] ["src/libFFmpeg-stubs.a"];

  ctypes_rules "src/FFmpegGenGen-c" "src/FFmpegGen.byte" "src/FFmpegGenGen" "src/FFmpegGeneratedCTypes.ml";
  dep ["compile"; "ctypes"] ["src/FFmpegGeneratedCTypes.cmi"];

  (* test *)
  ocaml_lib ~byte:true ~native:true ~extern:false ~dir:"src" "src/libFFmpeg";
  flag ["use_libFFmpeg"; "ocaml"; "compile"] (S[A"-I"; A"src"]);
  dep ["compile"; "use_libFFmpeg"] ["src/FFmpeg3.cmi"];
  dep ["link_FFmpeg"] ["src/libFFmpeg-stubs.a"];
  flag ["link_FFmpeg"; "byte"] (S [A "-cclib"; A"src/libFFmpeg-stubs.a"; S (cclibify @@ Lazy.force ffmpeg_libs)]);
  flag ["link_FFmpeg"; "native"] (S [A "-ccopt"; A"-Lsrc"; A "-cclib"; A"src/libFFmpeg-stubs.a"; S (cclibify @@ Lazy.force ffmpeg_libs)])

let _ = dispatch begin function
  | Before_options ->
    Options.use_ocamlfind := true
  | After_rules ->
    setup_ffmpeg ();

    flag ["c"; "compile"; "use_ctypes"] (S[A"-ccopt"; A"-I"; A"-ccopt"; A ctypes.Findlib.location]);

    (* flag ["link"] (S[A"-cclib"; A"-ltcmalloc"]); *)

    rule "Version file" ~prods:[version_file] (fun env _ -> Echo ([version_content ()], version_file))

  | _ -> ()
end

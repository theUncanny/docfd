open Cmdliner
open Lwd_infix
open Docfd_lib

let stdin_is_atty () =
  Unix.isatty Unix.stdin

let stdout_is_atty () =
  Unix.isatty Unix.stdout

let max_depth_arg_name = "max-depth"

let max_depth_arg =
  let doc =
    "Scan up to N levels in the file tree."
  in
  Arg.(
    value
    & opt int Params.default_max_file_tree_depth
    & info [ max_depth_arg_name ] ~doc ~docv:"N"
  )

let exts_arg_name = "exts"

let exts_arg =
  let doc =
    "File extensions to use, comma separated."
  in
  Arg.(
    value
    & opt string Params.default_recognized_exts
    & info [ exts_arg_name ] ~doc ~docv:"EXTS"
  )

let max_fuzzy_edit_dist_arg_name = "max-fuzzy-edit"

let max_fuzzy_edit_dist_arg =
  let doc =
    "Maximum edit distance for fuzzy matches."
  in
  Arg.(
    value
    & opt int Params.default_max_fuzzy_edit_distance
    & info [ max_fuzzy_edit_dist_arg_name ] ~doc ~docv:"N"
  )

let max_word_search_dist_arg_name = "max-word-search-dist"

let max_word_search_dist_arg =
  let doc =
    "Maximum distance to look for the next matching word/symbol in search phrase. If two words are adjacent words, then they are 1 distance away from each other. Note that contiguous spaces count as one word/symbol as well."
  in
  Arg.(
    value
    & opt int Params.default_max_word_search_distance
    & info [ max_word_search_dist_arg_name ] ~doc ~docv:"N"
  )

let index_chunk_word_count_arg_name = "index-chunk-word-count"

let index_chunk_word_count_arg =
  let doc =
    "Number of words to send as a task unit to the thread pool for indexing."
  in
  Arg.(
    value
    & opt int Params.default_index_chunk_word_count
    & info [ index_chunk_word_count_arg_name ] ~doc ~docv:"N"
  )

let debug_arg =
  let doc =
    Fmt.str "Display debug info."
  in
  Arg.(value & flag & info [ "debug" ] ~doc)

let list_files_recursively (dir : string) : string list =
  let l = ref [] in
  let add x =
    l := x :: !l
  in
  let rec aux depth path =
    if depth >= !Params.max_file_tree_depth then ()
    else (
      match Sys.is_directory path with
      | is_dir -> (
          if is_dir then (
            let next_choices =
              try
                Sys.readdir path
              with
              | _ -> [||]
            in
            Array.iter (fun f ->
                aux (depth + 1) (Filename.concat path f)
              )
              next_choices
          ) else (
            let ext = Filename.extension path in
            if List.mem ext !Params.recognized_exts then (
              add path
            )
          )
        )
      | exception _ -> ()
    )
  in
  aux 0 dir;
  !l

let open_text_path index ~editor ~path ~search_result =
  let path = Filename.quote path in
  let fallback = Fmt.str "%s %s" editor path in
  let cmd =
    match search_result with
    | None -> fallback
    | Some search_result -> (
        let first_word = List.hd @@ Search_result.found_phrase search_result in
        let first_word_loc = Index.loc_of_pos first_word.Search_result.found_word_pos index in
        let line_num = first_word_loc
                       |> Index.Loc.line_loc
                       |> Index.Line_loc.line_num_in_page
                       |> (fun x -> x + 1)
        in
        match Filename.basename editor with
        | "nano" ->
          Fmt.str "%s +%d %s" editor line_num path
        | "nvim" | "vim" | "vi" ->
          Fmt.str "%s +%d %s" editor line_num path
        | "kak" ->
          Fmt.str "%s +%d %s" editor line_num path
        | "hx" ->
          Fmt.str "%s %s:%d" editor path line_num
        | "emacs" ->
          Fmt.str "%s +%d %s" editor line_num path
        | "micro" ->
          Fmt.str "%s %s:%d" editor path line_num
        | _ ->
          fallback
      )
  in
  Sys.command cmd |> ignore

let run
    ~(env : Eio_unix.Stdenv.base)
    (debug : bool)
    (max_depth : int)
    (max_fuzzy_edit_dist : int)
    (max_word_search_dist : int)
    (index_chunk_word_count : int)
    (exts : string)
    (files : string list)
  =
  if max_depth < 1 then (
    Fmt.pr "Invalid %s: cannot be < 1\n" max_depth_arg_name;
    exit 1
  );
  if max_fuzzy_edit_dist < 0 then (
    Fmt.pr "Invalid %s: cannot be < 0\n" max_fuzzy_edit_dist_arg_name;
    exit 1
  );
  if max_word_search_dist < 1 then (
    Fmt.pr "Invalid %s: cannot be < 1\n" max_word_search_dist_arg_name;
    exit 1
  );
  if index_chunk_word_count < 1 then (
    Fmt.pr "Invalid %s: cannot be < 1\n" index_chunk_word_count_arg_name;
    exit 1
  );
  Params.debug := debug;
  Params.max_file_tree_depth := max_depth;
  Params.max_fuzzy_edit_distance := max_fuzzy_edit_dist;
  Params.max_word_search_distance := max_word_search_dist;
  Params.index_chunk_word_count := index_chunk_word_count;
  let recognized_exts =
    String.split_on_char ',' exts
    |> List.map (fun s ->
        s
        |> Misc_utils.remove_leading_dots
        |> CCString.trim
      )
    |> List.filter (fun s -> s <> "")
    |> List.map (fun s -> Printf.sprintf ".%s" s)
  in
  (match recognized_exts with
   | [] -> (
       Fmt.pr "Error: No usable file extensions\n";
       exit 1
     )
   | _ -> ()
  );
  Params.recognized_exts := recognized_exts;
  List.iter (fun file ->
      if not (Sys.file_exists file) then (
        Fmt.pr "Error: File \"%s\" does not exist\n" file;
        exit 1
      )
    )
    files;
  if !Params.debug then (
    Printf.printf "Scanning for documents\n"
  );
  (match Sys.getenv_opt "HOME" with
   | None -> (
       Fmt.pr "Env variable HOME is not set\n";
       exit 1
     )
   | Some home -> (
       Params.index_dir := Filename.concat home Params.index_dir_name;
     )
  );
  (match Sys.getenv_opt "VISUAL", Sys.getenv_opt "EDITOR" with
   | None, None -> (
       Printf.printf "Error: Environment variable VISUAL or EDITOR needs to be set\n";
       exit 1
     )
   | Some editor, _
   | None, Some editor -> (
       Params.text_editor := editor;
     )
  );
  let compute_init_ui_mode_and_document_src () : Ui_base.ui_mode * Ui_base.document_src =
    if not (stdin_is_atty ()) then
      match File_utils.read_in_channel_to_tmp_file stdin with
      | Ok tmp_file -> (
          Ui_base.(Ui_single_file, Stdin tmp_file)
        )
      | Error msg -> (
          Fmt.pr "Error: %s" msg;
          exit 1
        )
    else (
      match files with
      | [] -> Ui_base.(Ui_multi_file, Files [])
      | [ f ] -> (
          if Sys.is_directory f then
            Ui_base.(Ui_multi_file, Files (list_files_recursively f))
          else
            Ui_base.(Ui_single_file, Files [ f ])
        )
      | _ -> (
          Ui_base.(Ui_multi_file,
                   Files (
                     files
                     |> List.to_seq
                     |> Seq.flat_map (fun f ->
                         if Sys.is_directory f then
                           List.to_seq (list_files_recursively f)
                         else
                           Seq.return f
                       )
                     |> List.of_seq
                     |> List.sort_uniq String.compare
                   )
                  )
        )
    )
  in
  let compute_document_src () =
    snd (compute_init_ui_mode_and_document_src ())
  in
  let init_ui_mode, init_document_src =
    compute_init_ui_mode_and_document_src ()
  in
  if !Params.debug then (
    Printf.printf "Scanning completed\n"
  );
  if !Params.debug then (
    match init_document_src with
    | Stdin _ -> Printf.printf "Document source: stdin\n"
    | Files files -> (
        Printf.printf "Document source: files\n";
        List.iter (fun file ->
            Printf.printf "File: %s\n" file;
          )
          files
      )
  );
  (match init_document_src with
   | Stdin _ -> ()
   | Files files -> (
       if List.exists Misc_utils.path_is_pdf files then (
         if not (Proc_utils.command_exists "pdftotext") then (
           Fmt.pr "Error: Command pdftotext not found\n";
           exit 1
         )
       )
     )
  );
  let document_store_of_document_src document_src =
    let all_documents =
      match document_src with
      | Ui_base.Stdin path -> (
          match Document.of_path ~env path with
          | Ok x -> [ x ]
          | Error msg ->  (
              Fmt.pr "Error: %s" msg;
              exit 1
            )
        )
      | Files files -> (
          Eio.Fiber.List.filter_map (fun path ->
              match Document.of_path ~env path with
              | Ok x -> Some x
              | Error _ -> None) files
        )
    in
    all_documents
    |> List.to_seq
    |> Document_store.of_seq
  in
  Ui_base.Vars.init_ui_mode := init_ui_mode;
  let init_document_store = document_store_of_document_src init_document_src in
  Lwd.set Ui_base.Vars.document_store init_document_store;
  (match init_ui_mode with
   | Ui_base.Ui_single_file -> Lwd.set Ui_base.Vars.Single_file.document_store init_document_store
   | _ -> ()
  );
  (match init_document_src with
   | Stdin _ -> (
       let input =
         Unix.(openfile "/dev/tty" [ O_RDWR ] 0666)
       in
       Ui_base.Vars.term := Some (Notty_unix.Term.create ~input ())
     )
   | Files _ -> (
       Ui_base.Vars.term := Some (Notty_unix.Term.create ());
     )
  );
  Ui_base.Vars.eio_env := Some env;
  Lwd.set Ui_base.Vars.ui_mode init_ui_mode;
  let root : Nottui.ui Lwd.t =
    let$* ui_mode : Ui_base.ui_mode = Lwd.get Ui_base.Vars.ui_mode in
    match ui_mode with
    | Ui_multi_file -> Multi_file_view.main
    | Ui_single_file -> Single_file_view.main
  in
  let term = Ui_base.term () in
  let rec loop () =
    Ui_base.Vars.action := None;
    Lwd.set Ui_base.Vars.quit false;
    Ui_base.ui_loop
      ~quit:Ui_base.Vars.quit
      ~term
      root;
    match !Ui_base.Vars.action with
    | None -> ()
    | Some action -> (
        match action with
        | Ui_base.Recompute_document_src -> (
            let document_src = compute_document_src () in
            Lwd.set Ui_base.Vars.document_store (document_store_of_document_src document_src);
            loop ()
          )
        | Open_file_and_search_result (doc, search_result) -> (
            (match doc.path with
             | None -> ()
             | Some path ->
               if Misc_utils.path_is_pdf path then (
                 Proc_utils.run_in_background (Fmt.str "xdg-open %s" (Filename.quote path)) |> ignore;
               ) else (
                 let old_stats = Unix.stat path in
                 open_text_path
                   doc.index
                   ~editor:!Params.text_editor
                   ~path
                   ~search_result;
                 let new_stats = Unix.stat path in
                 if Float.abs (new_stats.st_mtime -. old_stats.st_mtime) >= 0.000_001 then (
                   (match Lwd.peek Ui_base.Vars.ui_mode with
                    | Ui_single_file -> Single_file_view.reload_document doc
                    | Ui_multi_file -> Multi_file_view.reload_document doc
                   );
                 );
               )
            );
            loop ()
          )
      )
  in
  loop ();
  (match init_document_src with
   | Stdin tmp_file -> (
       try
         Sys.remove tmp_file
       with
       | _ -> ()
     )
   | Files _ -> ()
  );
  Notty_unix.Term.release term

let files_arg = Arg.(value & pos_all string [ "." ] & info [])

let cmd ~env =
  let doc = "TUI multiline fuzzy document finder" in
  let version = Version_string.s in
  Cmd.v (Cmd.info "docfd" ~version ~doc)
    Term.(const (run ~env)
          $ debug_arg
          $ max_depth_arg
          $ max_fuzzy_edit_dist_arg
          $ max_word_search_dist_arg
          $ index_chunk_word_count_arg
          $ exts_arg
          $ files_arg)

let () = Eio_main.run (fun env ->
    exit (Cmd.eval (cmd ~env))
  )

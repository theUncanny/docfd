open Result_syntax
open Docfd_lib

type t = {
  path : string;
  title : string option;
  index : Index.t;
}

let make ~path : t =
  {
    path;
    title = None;
    index = Index.make ();
  }

let copy (t : t) =
  {
    path = t.path;
    title = t.title;
    index = t.index;
  }

type work_stage =
  | Title
  | Content

let parse_lines ~path (s : string Seq.t) : t =
  let rec aux (stage : work_stage) title s =
    match stage with
    | Content -> (
        let index = Index.of_lines s in
        let empty = make ~path in
        {
          empty with
          title;
          index;
        }
      )
    | Title -> (
        match s () with
        | Seq.Nil -> aux Content title Seq.empty
        | Seq.Cons (x, xs) -> (
            aux Content (Some (Misc_utils.sanitize_string x)) (Seq.cons x xs)
          )
      )
  in
  aux Title None s

let parse_pages ~path (s : string list Seq.t) : t =
  let rec aux (stage : work_stage) title s =
    match stage with
    | Content -> (
        let index = Index.of_pages s in
        let empty = make ~path in
        {
          empty with
          title;
          index;
        }
      )
    | Title -> (
        match s () with
        | Seq.Nil -> aux Content title Seq.empty
        | Seq.Cons (x, xs) -> (
            let title =
              match x with
              | [] -> None
              | x :: _ ->
                Some (Misc_utils.sanitize_string x)
            in
            aux Content title (Seq.cons x xs)
          )
      )
  in
  aux Title None s

let save_index ~env ~hash index =
  let fs = Eio.Stdenv.fs env in
  (try
     Eio.Path.(mkdir ~perm:0o755 (fs / !Params.index_dir));
   with _ -> ());
  let path =
    Eio.Path.(fs / Filename.concat !Params.index_dir (Fmt.str "%s.index" hash))
  in
  let json = Index.to_json index in
  Eio.Path.save ~create:(`Or_truncate 0o644) path (Yojson.Safe.to_string json)

let find_index ~env ~hash : Index.t option =
  let fs = Eio.Stdenv.fs env in
  try
    let path =
      Eio.Path.(fs / Filename.concat !Params.index_dir (Fmt.str "%s.index" hash))
    in
    let json = Yojson.Safe.from_string (Eio.Path.load path) in
    Index.of_json json
  with
  | _ -> None

let of_text_path ~env path : (t, string) result =
  let fs = Eio.Stdenv.fs env in
  try
    Eio.Path.(with_lines (fs / path))
      (fun lines ->
         Ok (parse_lines ~path lines)
      )
  with
  | _ -> Error (Printf.sprintf "Failed to read file: %s" path)

let of_pdf_path ~env path : (t, string) result =
  let proc_mgr = Eio.Stdenv.process_mgr env in
  let rec aux acc page_num =
    let page_num_string = Int.to_string page_num in
    let cmd = [ "pdftotext"; "-f"; page_num_string; "-l"; page_num_string; path; "-" ] in
    match Proc_utils.run_return_stdout ~proc_mgr cmd with
    | None -> (
        parse_pages ~path (acc |> List.rev |> List.to_seq)
      )
    | Some page -> (
        aux (page :: acc) (page_num + 1)
      )
  in
  try
    Ok (aux [] 1)
  with
  | _ -> Error (Printf.sprintf "Failed to read file: %s" path)

let of_path ~(env : Eio_unix.Stdenv.base) path : (t, string) result =
  let* hash = BLAKE2B.hash_of_file ~env ~path in
  match find_index ~env ~hash with
  | Some index -> (
      let title =
        if Index.global_line_count index = 0 then
          None
        else
          Some (Index.line_of_global_line_num 0 index)
      in
      Ok { path; title; index }
    )
  | None -> (
      let+ t =
        if Misc_utils.path_is_pdf path then
          of_pdf_path ~env path
        else
          of_text_path ~env path
      in
      save_index ~env ~hash t.index;
      t
    )

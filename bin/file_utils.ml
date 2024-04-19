open Misc_utils
open Debug_utils

let extension_of_file (s : string) =
  Filename.extension s
  |> String.lowercase_ascii

type file_format = [ `PDF | `Pandoc_supported_format | `Text ] [@@deriving ord]

module File_format_set = CCSet.Make (struct
    type t = file_format

    let compare = compare_file_format
  end)

let format_of_file (s : string) : file_format =
  let ext = extension_of_file s in
  if ext = ".pdf" then (
    `PDF
  ) else if List.mem ext Params.pandoc_supported_exts then (
    `Pandoc_supported_format
  ) else (
    `Text
  )

type typ = [
  | `File
  | `Dir
]

let typ_of_path ~follow_symlinks (path : string) : typ option =
  let open Unix in
  let stat =
    if follow_symlinks then
      stat path
    else
      lstat path
  in
  match stat.st_kind with
  | S_REG -> Some `File
  | S_DIR -> Some `Dir
  | _ -> None

let path_of_parts parts =
  List.rev parts
  |> String.concat Filename.dir_sep
  |> (fun s -> Printf.sprintf "/%s" s)

let cwd_path_parts () =
  Sys.getcwd ()
  |> CCString.split ~by:Filename.dir_sep
  |> (fun l -> match l with
      | "" :: l -> l
      | _ -> failwith "unexpected case")
  |> List.rev

let normalize_path_to_absolute path =
  let rec aux acc path_parts =
    match path_parts with
    | [] -> path_of_parts acc
    | x :: xs -> (
        match x with
        | "" | "." -> aux acc xs
        | ".." -> (
            let acc =
              match acc with
              | [] -> []
              | _ :: xs -> xs
            in
            aux acc xs
          )
        | _ -> (
            aux (x :: acc) xs
          )
      )
  in
  match CCString.split ~by:Filename.dir_sep path with
  | "" :: l -> (
      (* Absolute path *)
      aux [] l
    )
  | l -> (
      aux (cwd_path_parts ()) l
    )

let read_in_channel_to_tmp_file (ic : in_channel) : (string, string) result =
  let file = Filename.temp_file "docfd-" ".txt" in
  try
    CCIO.with_out file (fun oc ->
        CCIO.copy_into ic oc
      );
    Ok file
  with
  | _ -> (
      Error (Fmt.str "failed to write stdin to %s" (Filename.quote file))
    )

let list_files_recursive_all (path : string) : String_set.t =
  let acc = ref String_set.empty in
  let add x =
    acc := String_set.add x !acc
  in
  let rec aux path =
    match typ_of_path ~follow_symlinks:!Params.follow_symlinks path with
    | Some `Dir -> (
        let next_choices =
          try
            Sys.readdir path
          with
          | _ -> [||]
        in
        Array.iter (fun f ->
            aux (Filename.concat path f)
          )
          next_choices
      )
    | Some `File -> (
        add path
      )
    | _ | exception _ -> ()
  in
  aux (normalize_path_to_absolute path);
  !acc

let list_files_recursive_filter_by_globs
    (globs : string Seq.t)
  : String_set.t =
  let acc = ref String_set.empty in
  let add x =
    acc := String_set.add x !acc
  in
  let compile_glob_re s =
    match Misc_utils.compile_glob_re s with
    | None -> (
        failwith (Fmt.str "expected subpath of a valid glob pattern to also be valid: \"%s\"" s)
      )
    | Some x -> x
  in
  let rec aux (path_parts : string list) (glob_parts : string list) =
    let path = path_of_parts path_parts in
    match
      typ_of_path ~follow_symlinks:!Params.follow_symlinks path,
      glob_parts
    with
    | Some `File, [] -> add path
    | Some `File, _ -> ()
    | Some `Dir, [] -> ()
    | Some `Dir, x :: xs -> (
        match x with
        | "" | "." -> aux path_parts xs
        | ".." -> (
            let path_parts =
              match path_parts with
              | [] -> []
              | _ :: xs -> xs
            in
            aux path_parts xs
          )
        | "**" -> (
            let re_string = String.concat Filename.dir_sep (path :: glob_parts) in
            do_if_debug (fun oc ->
                Printf.fprintf oc "Compiling glob regex using pattern: %s\n" re_string
              );
            let re = compile_glob_re re_string in
            list_files_recursive_all path
            |> String_set.iter (fun path ->
                if Re.execp re path then (
                  do_if_debug (fun oc ->
                      Printf.fprintf oc "Glob regex %s matches path %s\n" re_string path
                    );
                  add path
                )
              )
          )
        | _ -> (
            let re = compile_glob_re x in
            let next_choices =
              try
                Sys.readdir path
              with
              | _ -> [||]
            in
            Array.iter (fun f ->
                if Re.execp re f then (
                  aux (f :: path_parts) xs
                )
              )
              next_choices;
          )
      )
    | None, _ -> ()
    | exception _ -> ()
  in
  Seq.iter (fun glob ->
      let glob_parts = CCString.split ~by:Filename.dir_sep glob in
      match glob_parts with
      | "" :: rest -> (
          (* Absolute path *)
          aux [] rest
        )
      | _ -> (
          aux (cwd_path_parts ()) glob_parts
        )
    ) globs;
  !acc

let list_files_recursive_filter_by_exts
    ~(exts : string list)
    (paths : string Seq.t)
  : String_set.t =
  let acc = ref String_set.empty in
  let add x =
    acc := String_set.add x !acc
  in
  let rec aux depth path =
    let follow_symlinks = depth = 0 || !Params.follow_symlinks in 
    match typ_of_path ~follow_symlinks path with
    | Some `Dir -> (
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
      )
    | Some `File -> (
        let ext = extension_of_file path in
        if depth = 0 || List.mem ext exts then (
          add path
        )
      )
    | _ | exception _ -> ()
  in
  paths
  |> Seq.map normalize_path_to_absolute
  |> Seq.iter (fun x -> aux 0 x);
  !acc

let mkdir_recursive (dir : string) : unit =
  let rec aux acc parts =
    match parts with
    | [] -> ()
    | "" :: xs -> (
        aux Filename.dir_sep xs
      )
    | x :: xs -> (
        let acc = Filename.concat acc x in
        match Sys.is_directory acc with
        | true -> aux acc xs
        | false -> (
            exit_with_error_msg
              (Fmt.str "%s is not a directory" (Filename.quote acc))
          )
        | exception (Sys_error _) -> (
            do_if_debug (fun oc ->
                Printf.fprintf oc "Creating directory: %s\n" (Filename.quote acc)
              );
            (try
               Sys.mkdir acc 0o755
             with
             | _ -> (
                 exit_with_error_msg
                   (Fmt.str "failed to create directory: %s" (Filename.quote acc))
               )
            );
            aux acc xs
          )
      )
  in
  aux "" (CCString.split ~by:Filename.dir_sep dir)

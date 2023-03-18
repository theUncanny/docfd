let ci_string_set_of_list (l : string list) =
  l
  |> List.map String.lowercase_ascii
  |> String_set.of_list

let path_is_note path =
  let words =
    Filename.basename path
    |> String.lowercase_ascii
    |> String.split_on_char '.'
  in
  List.exists (fun s ->
      s = "note" || s = "notes") words

let first_n_chars_of_string_contains ~n s c =
  let s_len = String.length s in
  let s =
    if s_len <= n then
      s
    else
      String.sub s 0 n
  in
  String.contains s c
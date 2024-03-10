let ci_string_set_of_list (l : string list) =
  l
  |> List.map String.lowercase_ascii
  |> String_set.of_list

let first_n_chars_of_string_contains ~n s c =
  let s_len = String.length s in
  let s =
    if s_len <= n then
      s
    else
      String.sub s 0 n
  in
  String.contains s c

let char_is_usable c =
  let code = Char.code c in
  (0x20 <= code && code <= 0x7E)

let sanitize_string s =
  let s_len = String.length s in
  let bytes = Bytes.make s_len ' ' in
  let rec aux pos =
    if pos >= s_len then
      String.of_bytes bytes
    else (
      let decode = String.get_utf_8_uchar s pos in
      if Uchar.utf_decode_is_valid decode then (
        let c = String.get_uint8 s pos in
        if c land 0b1000_0000 = 0b0000_0000 then (
          if 0x20 <= c && c <= 0x7E then (
            Bytes.blit_string s pos bytes pos 1
          );
          aux (pos+1)
        ) else (
          let len = Uchar.utf_decode_length decode in
          Bytes.blit_string s pos bytes pos len;
          aux (pos+len)
        )
      ) else (
        aux (pos+1)
      )
    )
  in
  aux 0

let bound_selection ~choice_count (x : int) : int =
  max 0 (min (choice_count - 1) x)

let list_and_length_of_seq (s : 'a Seq.t) : int * 'a list =
  let len, acc =
    Seq.fold_left (fun (len, acc) x ->
        (len + 1, x :: acc)
      )
      (0, [])
      s
  in
  (len, List.rev acc)

let path_is (typ : [ `PDF | `Pandoc_supported_format ]) (s : string) =
  let exts =
    match typ with
    | `PDF -> [ ".pdf" ]
    | `Pandoc_supported_format ->
      [ ".epub"
      ; ".odt"
      ; ".docx"
      ; ".fb2"
      ; ".ipynb"
      ; ".html"
      ; ".htm"
      ]
  in
  List.mem (Filename.extension (String.lowercase_ascii s)) exts

let remove_leading_dots (s : string) =
  let str_len = String.length s in
  if str_len = 0 then (
    ""
  ) else (
    let rec aux pos =
      if pos < str_len then (
        if String.get s pos = '.' then
          aux (pos + 1)
        else (
          String.sub s pos (str_len - pos)
        )
      ) else (
        ""
      )
    in
    aux 0
  )

let div_round_to_closest x y =
  (x + y - 1) / y

let frequencies_of_words_ci (s : string Seq.t) : int String_map.t =
  Seq.fold_left (fun m word ->
      let word = String.lowercase_ascii word in
      let count = Option.value ~default:0
          (String_map.find_opt word m)
      in
      String_map.add word (count + 1) m
    )
    String_map.empty
    s

let opening_closing_symbol_pairs (l : string list) : (int * int) list =
  let _, pairs =
    CCList.foldi
      (fun ((m, pairs) : (int list Char_map.t) * ((int * int) list)) i s ->
         if String.length s = 1 then (
           let c = String.get s 0 in
           match List.assoc_opt c Params.opening_closing_symbols with
           | Some _ -> (
               let stack =
                 match Char_map.find_opt c m with
                 | None -> []
                 | Some l -> l
               in
               (Char_map.add c (i :: stack) m, pairs)
             )
           | None -> (
               match List.assoc_opt c Params.opening_closing_symbols_flipped with
               | Some corresponding_open_symbol -> (
                   let stack =
                     match Char_map.find_opt corresponding_open_symbol m with
                     | None -> []
                     | Some l -> l
                   in
                   match stack with
                   | [] -> (m, pairs)
                   | x :: xs -> (
                       (Char_map.add corresponding_open_symbol xs m, (x, i) :: pairs)
                     )
                 )
               | None -> (m, pairs)
             )
         ) else (
           (m, pairs)
         )
      )
      (Char_map.empty, [])
      l
  in
  pairs

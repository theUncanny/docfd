module Line_loc = struct
  type t = {
    page_num : int;
    line_num_in_page : int;
    global_line_num : int;
  }

  let page_num t = t.page_num

  let line_num_in_page t = t.line_num_in_page

  let global_line_num t = t.global_line_num

  let compare (x : t) (y : t) =
    Int.compare x.global_line_num y.global_line_num
end

module Line_loc_map = Map.Make (Line_loc)

module Loc = struct
  type t = {
    line_loc : Line_loc.t;
    pos_in_line : int;
  }

  let line_loc t = t.line_loc

  let pos_in_line t =  t.pos_in_line
end

type t = {
  pos_s_of_word_ci : Int_set.t Int_map.t;
  loc_of_pos : Loc.t Int_map.t;
  line_loc_of_global_line_num : Line_loc.t Int_map.t;
  global_line_num_of_line_loc : int Line_loc_map.t;
  start_end_inc_pos_of_global_line_num : (int * int) Int_map.t;
  word_ci_of_pos : int Int_map.t;
  word_of_pos : int Int_map.t;
  line_count_of_page : int Int_map.t;
  page_count : int;
  global_line_count : int;
}

type multi_indexed_word = {
  pos : int;
  loc : Loc.t;
  word : string;
}

type chunk = multi_indexed_word array

let empty : t = {
  pos_s_of_word_ci = Int_map.empty;
  loc_of_pos = Int_map.empty;
  line_loc_of_global_line_num = Int_map.empty;
  global_line_num_of_line_loc = Line_loc_map.empty;
  start_end_inc_pos_of_global_line_num = Int_map.empty;
  word_ci_of_pos = Int_map.empty;
  word_of_pos = Int_map.empty;
  line_count_of_page = Int_map.empty;
  page_count = 0;
  global_line_count = 0;
}

let union (x : t) (y : t) =
  {
    pos_s_of_word_ci =
      Int_map.union (fun _k s0 s1 -> Some (Int_set.union s0 s1))
        x.pos_s_of_word_ci
        y.pos_s_of_word_ci;
    loc_of_pos =
      Int_map.union (fun _k x _ -> Some x)
        x.loc_of_pos
        y.loc_of_pos;
    line_loc_of_global_line_num =
      Int_map.union (fun _k x _ -> Some x)
        x.line_loc_of_global_line_num
        y.line_loc_of_global_line_num;
    global_line_num_of_line_loc =
      Line_loc_map.union (fun _k x _ -> Some x)
        x.global_line_num_of_line_loc
        y.global_line_num_of_line_loc;
    start_end_inc_pos_of_global_line_num =
      Int_map.union (fun _k (start_x, end_inc_x) (start_y, end_inc_y) ->
          Some (min start_x start_y, max end_inc_x end_inc_y))
        x.start_end_inc_pos_of_global_line_num
        y.start_end_inc_pos_of_global_line_num;
    word_ci_of_pos =
      Int_map.union (fun _k x _ -> Some x)
        x.word_ci_of_pos
        y.word_ci_of_pos;
    word_of_pos =
      Int_map.union (fun _k x _ -> Some x)
        x.word_of_pos
        y.word_of_pos;
    line_count_of_page =
      Int_map.union (fun _k x y -> Some (max x y))
        x.line_count_of_page
        y.line_count_of_page;
    page_count = max x.page_count y.page_count;
    global_line_count = max x.global_line_count y.global_line_count;
  }

let global_line_count t = t.global_line_count

let words_of_lines
    (s : (Line_loc.t * string) Seq.t)
  : multi_indexed_word Seq.t =
  s
  |> Seq.flat_map (fun (line_loc, s) ->
      let seq = Tokenize.f_with_pos ~drop_spaces:false s in
      if Seq.is_empty seq then (
        let empty_word = ({ Loc.line_loc; pos_in_line = 0 }, "") in
        Seq.return empty_word
      ) else (
        Seq.map (fun (pos_in_line, word) ->
            ({ Loc.line_loc; pos_in_line }, word))
          seq
      )
    )
  |> Seq.mapi (fun pos (loc, word) ->
      { pos; loc; word })

let of_chunk (arr : chunk) : t =
  Array.fold_left
    (fun
      { pos_s_of_word_ci;
        loc_of_pos;
        line_loc_of_global_line_num;
        global_line_num_of_line_loc;
        start_end_inc_pos_of_global_line_num;
        word_ci_of_pos;
        word_of_pos;
        line_count_of_page;
        page_count;
        global_line_count;
      }
      { pos; loc; word } ->
      let line_loc = loc.Loc.line_loc in
      let global_line_num = line_loc.global_line_num in
      let word_ci = String.lowercase_ascii word in
      let index_of_word = Word_db.add word in
      let index_of_word_ci = Word_db.add word_ci in
      let pos_s = Option.value ~default:Int_set.empty
          (Int_map.find_opt index_of_word_ci pos_s_of_word_ci)
                  |> Int_set.add pos
      in
      let start_end_inc_pos =
        match Int_map.find_opt global_line_num start_end_inc_pos_of_global_line_num with
        | None -> (pos, pos)
        | Some (x, y) -> (min x pos, max y pos)
      in
      let cur_page_line_count =
        Option.value ~default:0
          (Int_map.find_opt line_loc.page_num line_count_of_page)
      in
      { pos_s_of_word_ci = Int_map.add index_of_word_ci pos_s pos_s_of_word_ci;
        loc_of_pos = Int_map.add pos loc loc_of_pos;
        line_loc_of_global_line_num =
          Int_map.add global_line_num line_loc line_loc_of_global_line_num;
        global_line_num_of_line_loc =
          Line_loc_map.add line_loc global_line_num global_line_num_of_line_loc;
        start_end_inc_pos_of_global_line_num =
          Int_map.add global_line_num start_end_inc_pos start_end_inc_pos_of_global_line_num;
        word_ci_of_pos = Int_map.add pos index_of_word_ci word_ci_of_pos;
        word_of_pos = Int_map.add pos index_of_word word_of_pos;
        line_count_of_page =
          Int_map.add line_loc.page_num (max cur_page_line_count (line_loc.line_num_in_page + 1)) line_count_of_page;
        page_count = max page_count (line_loc.page_num + 1);
        global_line_count = max global_line_count (global_line_num + 1);
      }
    )
    empty
    arr

let chunks_of_words (s : multi_indexed_word Seq.t) : chunk Seq.t =
  OSeq.chunks !Params.index_chunk_word_count s

let of_seq (s : (Line_loc.t * string) Seq.t) : t =
  let indices =
    s
    |> Seq.map (fun (line_loc, s) -> (line_loc, Misc_utils.sanitize_string s))
    |> words_of_lines
    |> chunks_of_words
    |> List.of_seq
    |> Eio.Fiber.List.map (fun chunk ->
        Task_pool.run (fun () -> of_chunk chunk))
  in
  List.fold_left (fun acc index ->
      union acc index
    )
    empty
    indices

let of_lines (s : string Seq.t) : t =
  s
  |> Seq.mapi (fun global_line_num line ->
      ({ Line_loc.page_num = 0; line_num_in_page = global_line_num; global_line_num }, line)
    )
  |> of_seq

let of_pages (s : string array Seq.t) : t =
  s
  |> Seq.mapi (fun page_num page ->
      (page_num, page)
    )
  |> Seq.flat_map (fun (page_num, page) ->
      if Array.length page = 0 then (
        let empty_line = ({ Line_loc.page_num; line_num_in_page = 0; global_line_num = 0 }, "") in
        Seq.return empty_line
      ) else (
        Array.to_seq page
        |> Seq.mapi (fun line_num_in_page line ->
            ({ Line_loc.page_num; line_num_in_page; global_line_num = 0 }, line)
          )
      )
    )
  |> Seq.mapi (fun global_line_num ((line_loc : Line_loc.t), line) ->
      ({ line_loc with global_line_num }, line)
    )
  |> of_seq

let word_ci_of_pos pos t =
  match Int_map.find_opt pos t.word_ci_of_pos with
  | None -> invalid_arg "Index.word_ci_of_pos: Cannot find pos"
  | Some x -> Word_db.word_of_index x

let word_of_pos pos t =
  match Int_map.find_opt pos t.word_of_pos with
  | None -> invalid_arg "Index.word_of_pos: Cannot find pos"
  | Some x -> Word_db.word_of_index x

let word_ci_and_pos_s ?range_inc t : (string * Int_set.t) Seq.t =
  match range_inc with
  | None -> (
      Int_map.to_seq t.pos_s_of_word_ci
      |> Seq.map (fun (i, s) -> (Word_db.word_of_index i, s))
    )
  | Some (start, end_inc) -> (
      assert (start <= end_inc);
      let _, _, m =
        Int_map.split (start-1) t.word_ci_of_pos
      in
      let m, _, _ =
        Int_map.split (end_inc+1) m
      in
      let words_to_consider =
        Int_map.fold (fun _ index set ->
            Int_set.add index set
          ) m Int_set.empty
      in
      Int_set.to_seq words_to_consider
      |> Seq.map (fun index ->
          (Word_db.word_of_index index, Int_map.find index t.pos_s_of_word_ci)
        )
      |> Seq.map (fun (word, pos_s) ->
          let _, _, m =
            Int_set.split (start-1) pos_s
          in
          let m, _, _ =
            Int_set.split (end_inc+1) m
          in
          (word, m)
        )
    )

let words_of_global_line_num x t : string Seq.t =
  if x >= global_line_count t then
    invalid_arg "Index.words_of_global_line_num: global_line_num out of range"
  else (
    let (start, end_inc) =
      Int_map.find x t.start_end_inc_pos_of_global_line_num
    in
    OSeq.(start -- end_inc)
    |> Seq.map (fun pos -> word_of_pos pos t)
  )

let line_of_global_line_num x t =
  if x >= global_line_count t then
    invalid_arg "Index.line_of_global_line_num: global_line_num out of range"
  else (
    words_of_global_line_num x t
    |> List.of_seq
    |> String.concat ""
  )

let line_loc_of_global_line_num x t =
  if x >= global_line_count t then
    invalid_arg "Index.line_loc_of_global_line_num: global_line_num out of range"
  else (
    Int_map.find x t.line_loc_of_global_line_num
  )

let loc_of_pos pos t : Loc.t =
  match Int_map.find_opt pos t.loc_of_pos with
  | None -> invalid_arg "Index.loc_of_pos: Cannot find pos"
  | Some x -> x

let line_count_of_page page t : int =
  match Int_map.find_opt page t.line_count_of_page with
  | None -> invalid_arg "Index.line_count_of_page: Cannot find page"
  | Some x -> x

module Search = struct
  let usable_positions
      ?around_pos
      ((search_word, dfa) : (string * Spelll.automaton))
      (t : t)
    : int Seq.t =
    let word_ci_and_positions_to_consider =
      match around_pos with
      | None -> word_ci_and_pos_s t
      | Some around_pos ->
        let start = around_pos - (!Params.max_word_search_range+1) in
        let end_inc = around_pos + (!Params.max_word_search_range+1) in
        word_ci_and_pos_s ~range_inc:(start, end_inc) t
    in
    let search_word_ci =
      String.lowercase_ascii search_word
    in
    word_ci_and_positions_to_consider
    |> Seq.filter (fun (indexed_word, _pos_s) ->
        (not (String.equal indexed_word ""))
        &&
        (not (String.for_all Parser_components.is_space indexed_word))
      )
    |> Seq.filter (fun (indexed_word, _pos_s) ->
        String.equal search_word_ci indexed_word
        || CCString.find ~sub:search_word_ci indexed_word >= 0
        || (Misc_utils.first_n_chars_of_string_contains ~n:5 indexed_word search_word_ci.[0]
            && Spelll.match_with dfa indexed_word)
      )
    |> Seq.flat_map (fun (_indexed_word, pos_s) -> Int_set.to_seq pos_s)

  let search_around_pos
      (around_pos : int)
      (l : (string * Spelll.automaton) list)
      (t : t)
    : int list Seq.t =
    let rec aux around_pos l =
      match l with
      | [] -> Seq.return []
      | (search_word, dfa) :: rest -> (
          usable_positions ~around_pos (search_word, dfa) t
          |> Seq.flat_map (fun pos ->
              aux pos rest
              |> Seq.map (fun l -> pos :: l)
            )
        )
    in
    aux around_pos l

  let search
      (phrase : Search_phrase.t)
      (t : t)
    : int list Seq.t =
    if Search_phrase.is_empty phrase then
      Seq.empty
    else (
      match List.combine phrase.phrase phrase.fuzzy_index with
      | [] -> failwith "Unexpected case"
      | first_word :: rest -> (
          let possible_start_count, possible_starts =
            usable_positions first_word t
            |> Misc_utils.list_and_length_of_seq
          in
          if possible_start_count = 0 then
            Seq.empty
          else (
            let search_limit_per_start =
              max
                1
                (
                  (Params.search_result_limit + possible_start_count - 1) / possible_start_count
                )
            in
            possible_starts
            |> Eio.Fiber.List.map (fun pos ->
                Task_pool.run
                  (fun () ->
                     search_around_pos pos rest t
                     |> Seq.map (fun l -> pos :: l)
                     |> Seq.take search_limit_per_start
                     |> List.of_seq
                  )
              )
            |> List.fold_left (fun s (l : int list list) ->
                Seq.append s (List.to_seq l)
              )
              Seq.empty
          )
        )
    )
end

let search
    (phrase : Search_phrase.t)
    (t : t)
  : Search_result.t array =
  let arr =
    Search.search phrase t
    |> Seq.map (fun l ->
        Search_result.make
          ~search_phrase:phrase.phrase
          ~found_phrase:(List.map
                           (fun pos ->
                              (pos,
                               word_ci_of_pos pos t,
                               word_of_pos pos t
                              )
                           ) l)
      )
    |> Array.of_seq
  in
  Array.sort Search_result.compare arr;
  arr

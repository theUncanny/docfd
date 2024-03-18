type t

val empty : t

val is_empty : t -> bool

val fuzzy_max_edit_distance : t -> int

val flattened : t -> Search_phrase.t list

val make : fuzzy_max_edit_distance:int -> string -> t option

val equal : t -> t -> bool

(** Position in an Isabelle file *)
type t = {
  line : int;
  column : int;
  file : string;
}

let create ~line ~column ~file = { line; column; file }

let to_string { line; column; file } =
  Printf.sprintf "%s:%d:%d" file line column

let compare p1 p2 =
  match String.compare p1.file p2.file with
  | 0 -> (
      match Int.compare p1.line p2.line with
      | 0 -> Int.compare p1.column p2.column
      | n -> n)
  | n -> n

let equal p1 p2 =
  p1.line = p2.line && p1.column = p2.column && p1.file = p2.file

let hash { line; column; file } =
  Hashtbl.hash (line, column, file)

(** Parse position from string format "file:line:column" *)
let from_string s =
  match String.split_on_char ':' s with
  | [file; line; column; _] ->
      Some { file; line = int_of_string line; column = int_of_string column }
  | [file; line; column] ->
      Some { file; line = int_of_string line; column = int_of_string column }
  | [file; line] ->
      Some { file; line = int_of_string line; column = 0 }
  | [file] ->
      Some { file; line = 0; column = 0 }
  | _ -> None

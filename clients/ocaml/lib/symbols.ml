(** Isabelle symbol management *)

(** Mapping from ASCII symbols to Unicode *)
type symbol_table = (string, string) Hashtbl.t

(** Cached symbol tables *)
type symbol_cache = {
  symbols : symbol_table;
  reverse_symbols : symbol_table;
}

let symbol_cache : symbol_cache option ref = ref None

(** Subscript and superscript translation tables *)
let subsup_trans_table = [
  ("⇩0", "₀"); ("⇩1", "₁"); ("⇩2", "₂"); ("⇩3", "₃"); ("⇩4", "₄");
  ("⇩5", "₅"); ("⇩6", "₆"); ("⇩7", "₇"); ("⇩8", "₈"); ("⇩9", "₉");
  ("⇧0", "⁰"); ("⇧1", "¹"); ("⇧2", "²"); ("⇧3", "³"); ("⇧4", "⁴");
  ("⇧5", "⁵"); ("⇧6", "⁶"); ("⇧7", "⁷"); ("⇧8", "⁸"); ("⇧9", "⁹");
  ("⇩-", "₋"); ("⇧-", "⁻"); ("⇩+", "₊"); ("⇧+", "⁺"); ("⇩=", "₌"); ("⇧=", "⁼");
  ("⇩(", "₍"); ("⇧(", "⁽"); ("⇩)", "₎"); ("⇧)", "⁾");
]

let subsup_restore_table =
  List.map (fun (a, b) -> (b, a)) subsup_trans_table

(** Load symbols from a file *)
let load_symbols path symbols reverse_symbols =
  if not (Sys.file_exists path) then
    (symbols, reverse_symbols)
  else
    let ic = open_in path in
    let rec read_lines () =
      try
        let line = input_line ic in
        let line = String.trim line in
        if line = "" || String.get line 0 = '#' then
          read_lines ()
        else begin
          (* Parse line format: \<odiv>  code: 0x002A38  font: PhiSymbols ... *)
          let parts = String.split_on_char ' ' line |> List.filter (fun s -> s <> "") in
          match parts with
          | [] -> read_lines ()
          | symbol :: rest ->
              (* Find "code:" part *)
              let rec find_code = function
                | [] -> None
                | "code:" :: hex :: _ -> Some hex
                | s :: rest when String.starts_with ~prefix:"code:" s ->
                    let hex = String.sub s 5 (String.length s - 5) in
                    if hex = "" then find_code rest else Some hex
                | _ :: rest -> find_code rest
              in
              (match find_code rest with
               | Some hex_str ->
                   (try
                      let code = int_of_string hex_str in
                      let unicode_char = Printf.sprintf "%c" (Char.chr code) in
                      Hashtbl.replace symbols symbol unicode_char;
                      Hashtbl.replace reverse_symbols unicode_char symbol;
                    with _ -> ());
                   read_lines ()
               | None -> read_lines ())
        end
      with End_of_file ->
        close_in ic;
        (symbols, reverse_symbols)
    in
    read_lines ()

(** Get Isabelle symbol tables *)
let get_symbols_and_reversed () =
  match !symbol_cache with
  | Some cache -> cache
  | None ->
      let isabelle_home =
        let ic = Unix.open_process_in "isabelle getenv -b ISABELLE_HOME" in
        let home = input_line ic in
        close_in ic;
        String.trim home
      in
      let isabelle_home_user =
        let ic = Unix.open_process_in "isabelle getenv -b ISABELLE_HOME_USER" in
        let home = input_line ic in
        close_in ic;
        String.trim home
      in
      let symbols = Hashtbl.create 1000 in
      let reverse_symbols = Hashtbl.create 1000 in
      let files = [
        isabelle_home ^ "/etc/symbols";
        isabelle_home_user ^ "/etc/symbols";
      ] in
      let (symbols, reverse_symbols) =
        List.fold_left
          (fun (syms, rev_syms) file -> load_symbols file syms rev_syms)
          (symbols, reverse_symbols)
          files
      in
      let cache = { symbols; reverse_symbols } in
      symbol_cache := Some cache;
      cache

let get_symbols () =
  (get_symbols_and_reversed ()).symbols

let get_reverse_symbols () =
  (get_symbols_and_reversed ()).reverse_symbols

(** Convert ASCII notation to Unicode *)
let pretty_unicode src =
  let symbols = get_symbols () in
  (* Replace \<...> patterns *)
  let pattern = Re.Perl.compile_pat {|\\<[^>]+>|} in
  let src = Re.replace pattern src ~f:(fun g ->
    let matched = Re.Group.get g 0 in
    try Hashtbl.find symbols matched
    with Not_found -> matched
  ) in
  (* Replace subscript/superscript patterns *)
  List.fold_left (fun s (from, to_) ->
    Str.global_replace (Str.regexp_string from) to_ s
  ) src subsup_trans_table

let unicode_of_ascii = pretty_unicode

(** Convert Unicode to ASCII notation *)
let ascii_of_unicode src =
  let reverse_symbols = get_reverse_symbols () in
  (* First restore subscript/superscript *)
  let src = List.fold_left (fun s (from, to_) ->
    Str.global_replace (Str.regexp_string from) to_ s
  ) src subsup_restore_table in
  (* Then replace Unicode symbols with ASCII *)
  let buf = Buffer.create (String.length src) in
  String.iter (fun c ->
    let s = String.make 1 c in
    try
      let ascii = Hashtbl.find reverse_symbols s in
      Buffer.add_string buf ascii
    with Not_found ->
      Buffer.add_char buf c
  ) src;
  Buffer.contents buf

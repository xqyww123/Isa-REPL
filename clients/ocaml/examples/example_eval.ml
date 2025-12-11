(** Example: Basic evaluation

    USAGE: example_eval.exe <ADDRESS OF SERVER>

    This script demonstrates the basic usage of REPL.
*)

open Isa_repl

let usage = "USAGE: example_eval.exe <ADDRESS OF SERVER>\n\
             \n\
             This script demonstrates the basic usage of REPL."

let echo_eval client src =
  Printf.printf ">>> %s\n" (String.concat "\n>>> " (String.split_on_char '\n' src));
  let result = eval client src in
  Printf.printf "Result: %s\n\n" (Msgpck.show result);
  result

let () =
  if Array.length Sys.argv <> 2 then begin
    Printf.eprintf "%s\n" usage;
    exit 1
  end;

  let addr = Sys.argv.(1) in
  let client = create addr "HOL" in

  try
    let _ = echo_eval client {|
section \<open>The datatype of finite lists\<close>

theory MyList
imports Sledgehammer Lifting_Set
begin
|} in

    let _ = echo_eval client {|
datatype (set: 'a) list =
    Nil  ("[]")
  | Cons (hd: 'a) (tl: "'a list")  (infixr "#" 65)
for
  map: map
  rel: list_all2
  pred: list_all
where
  "tl [] = []"

context begin
lemma
  "(1::int) + 2 = 3"
  by smt
end

notepad begin
end

definition "ONE = (1::nat)"
end

theory HHH
  imports MyList
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end

theory GGG
  imports HHH
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end

theory KKK
  imports HHH
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end
|} in

    close client;
    Printf.printf "Done!\n"

  with
  | REPLFail msg ->
      Printf.eprintf "REPL Error: %s\n" msg;
      close client;
      exit 1
  | e ->
      Printf.eprintf "Error: %s\n" (Printexc.to_string e);
      close client;
      exit 1

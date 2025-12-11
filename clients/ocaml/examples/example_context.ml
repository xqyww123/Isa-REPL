(** Example: Retrieving proof context

    This script demonstrates how to retrieve the proof context that includes useful contextual data
    including local facts, assumptions, bindings (made by `let` command),
    fixed term variables (and their types), fixed type variables (and their sorts), and goals.
*)

open Isa_repl

let usage = "USAGE: example_context.exe <ADDRESS OF SERVER>\n\
             \n\
             This script demonstrates how to retrieve the proof context."

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
theory HHH
imports Main
begin

lemma "Assumption1 (x::nat) ==> Assumption2 (y::int) ==> Qiyuan Great \<and> Worship Qiyuan"
subgoal premises prems proof
  have lem: "1 + 1 = (2::nat)" by auto
|} in

    Printf.printf "\nContext (typed_pretty):\n";
    let ctx = context ~pp:"typed_pretty" client in
    Printf.printf "%s\n" (Msgpck.show ctx);

    close client;
    Printf.printf "\nDone!\n"

  with
  | REPLFail msg ->
      Printf.eprintf "REPL Error: %s\n" msg;
      close client;
      exit 1
  | e ->
      Printf.eprintf "Error: %s\n" (Printexc.to_string e);
      close client;
      exit 1

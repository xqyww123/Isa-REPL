(** Example: State rollback

    This script demonstrates the basic usage of state rollback.
*)

open Isa_repl

let usage = "USAGE: example_rollback.exe <ADDRESS OF SERVER>\n\
             \n\
             This script demonstrates the basic usage of state rollback."

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
lemma "\<exists>x::nat. x + 1 = 2"
|} in

    Printf.printf "Recording state S0...\n";
    record_state client "S0";

    let _ = echo_eval client {|
    apply (rule exI[where x=666])
|} in

    Printf.printf "Recording state S1...\n";
    record_state client "S1";

    Printf.printf "\nRecorded histories:\n";
    let hist = history client in
    Printf.printf "%s\n\n" (Msgpck.show hist);

    Printf.printf "Rollback to state S0\n";
    let rollback_result = rollback client "S0" in
    Printf.printf "%s\n\n" (Msgpck.show rollback_result);

    let _ = echo_eval client {|
    by (rule exI[where x=1], auto)
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

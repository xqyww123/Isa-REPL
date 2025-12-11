(** Basic usage example for Isa-REPL OCaml client *)

open Isa_repl

let () =
  (* Connect to Isabelle REPL server *)
  Printf.printf "Connecting to Isabelle REPL server...\n%!";
  let client = create "localhost:9000" "HOL" in

  try
    (* Evaluate a simple theory *)
    Printf.printf "Evaluating theory...\n%!";
    let result = eval client "theory Test imports Main begin end" in
    Printf.printf "Evaluation result: %s\n%!" (Msgpck.show result);

    (* Lex some source code *)
    Printf.printf "\nLexing source code...\n%!";
    let source = "
      lemma example: \"True\"
        by auto

      lemma another: \"False ==> False\"
        by auto
    " in
    let commands = lex client source in
    Printf.printf "Lexed commands: %s\n%!" (Msgpck.show commands);

    (* Record state *)
    Printf.printf "\nRecording state...\n%!";
    record_state client "checkpoint";

    (* Evaluate a lemma *)
    Printf.printf "Evaluating lemma...\n%!";
    let _ = eval client "lemma test: \"True\" by auto" in

    (* Rollback *)
    Printf.printf "Rolling back...\n%!";
    let _ = rollback client "checkpoint" in

    (* Clean up *)
    Printf.printf "Cleaning up...\n%!";
    clean_history client;
    close client;
    Printf.printf "Done!\n%!"

  with
  | REPLFail msg ->
      Printf.eprintf "REPL Error: %s\n%!" msg;
      close client;
      exit 1
  | e ->
      Printf.eprintf "Error: %s\n%!" (Printexc.to_string e);
      close client;
      exit 1

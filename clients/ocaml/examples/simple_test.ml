(** Simple test - just connect and do minimal operations *)

open Isa_repl

let () =
  if Array.length Sys.argv <> 2 then begin
    Printf.eprintf "USAGE: simple_test.exe <ADDRESS>\n";
    exit 1
  end;

  let addr = Sys.argv.(1) in
  Printf.printf "Connecting to %s...\n" addr;

  try
    let client = create addr "HOL" in
    Printf.printf "✓ Connected successfully!\n";

    Printf.printf "\nEvaluating simple theory...\n";
    let result = eval client "theory Test imports Main begin end" in
    Printf.printf "✓ Evaluation result: %s\n\n" (Msgpck.show result);

    Printf.printf "Closing connection...\n";
    close client;
    Printf.printf "✓ Done!\n";
    exit 0

  with
  | REPLFail msg ->
      Printf.eprintf "✗ REPL Error: %s\n" msg;
      exit 1
  | Unix.Unix_error (err, fn, arg) ->
      Printf.eprintf "✗ Unix error in %s(%s): %s\n" fn arg (Unix.error_message err);
      exit 1
  | e ->
      Printf.eprintf "✗ Error: %s\n" (Printexc.to_string e);
      Printexc.print_backtrace stderr;
      exit 1

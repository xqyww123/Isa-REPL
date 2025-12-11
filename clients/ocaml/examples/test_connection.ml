(** Test server connection *)

open Isa_repl

let () =
  if Array.length Sys.argv <> 2 then begin
    Printf.eprintf "USAGE: test_connection.exe <ADDRESS>\n";
    exit 1
  end;

  let addr = Sys.argv.(1) in
  Printf.printf "Testing connection to %s...\n" addr;

  try
    test_server addr;
    Printf.printf "✓ Server is reachable and responding!\n";
    exit 0
  with
  | REPLFail msg ->
      Printf.eprintf "✗ Connection failed: %s\n" msg;
      exit 1
  | Unix.Unix_error (err, _, _) ->
      Printf.eprintf "✗ Network error: %s\n" (Unix.error_message err);
      exit 1
  | e ->
      Printf.eprintf "✗ Error: %s\n" (Printexc.to_string e);
      exit 1

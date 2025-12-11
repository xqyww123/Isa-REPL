(** Example: Plugin system

    This example demonstrates how to install and uninstall plugins.
    A plugin allows clients to access any internal representation of Isabelle.
*)

open Isa_repl

let usage = "USAGE: example_plugin.exe <ADDRESS OF SERVER>"

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
    Printf.printf "This example demonstrates how to install and uninstall plugins.\n";
    Printf.printf "A plugin allows clients to access any internal representation of Isabelle.\n\n";

    (* This plugin collects all variables in a proof state. *)
    let ml_code = {|
let open MessagePackBinIO.Pack
    fun packType ctxt = packString o REPL.trim_makrup o Syntax.string_of_typ ctxt
    fun collect_vars s =
        let val ctxt = Toplevel.context_of s
            val goal = Toplevel.proof_of s
                    |> Proof.goal
                    |> #goal
            val vars = Term.add_frees (Thm.prop_of goal) []
         in packPairList (packString, packType ctxt) vars
        end
 in fn cfg => fn {state=s,...} => (
        (if Toplevel.is_proof s then SOME (collect_vars s) else NONE),
        NONE) (*this plugin doesn't alter the evaluation state*)
end
|} in

    Printf.printf "Installing plugin 'VARS'...\n";
    let _ = plugin client ~name:"VARS" ~ml_code () in

    Printf.printf "Evaluating theory with lemma...\n";
    let _ = echo_eval client {|
theory TMP
    imports Main
begin
lemma "(a::nat) + b = b + a"
    by auto
end
|} in

    Printf.printf "\nYou should find something like this in the output for the `lemma` command:\n";
    Printf.printf "\"plugin_output\": {\n";
    Printf.printf "  \"VARS\": {\n";
    Printf.printf "    \"b\": \"nat\",\n";
    Printf.printf "    \"a\": \"nat\"\n";
    Printf.printf "  }\n";
    Printf.printf "}\n\n";

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

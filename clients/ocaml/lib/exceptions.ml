(** Exception raised when REPL operations fail *)
exception REPLFail of string

let () =
  Printexc.register_printer (function
    | REPLFail msg -> Some (Printf.sprintf "REPLFail: %s" msg)
    | _ -> None)

signature REPL = sig

datatype message_type = NORMAL | TRACING | WARNING
type message = message_type * string
type flags = {
        is_toplevel: bool,
        is_theory  : bool,
        is_proof   : bool,
        is_skipped_proof: bool
}
type command_output = {
        command_name : string,
        message: message list, (*text printed in Isabelle's output panel*)
        output : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        errors : string list
}
type command_outputs = {
        outputs: command_output list,
        error : string option
}

val init_repler : theory option -> unit
val RE : string -> command_outputs

type Worker_ID = int
val the_current_worker_ID  : unit -> Worker_ID option
val get_and_clean_message' : Worker_ID -> message list
val get_and_clean_message  : unit -> message list

end

structure REPL : REPL = struct

(** Tools **)

fun trim_makrup msg =
  let fun auto _ [] = []
        | auto acc (#"\005" :: L) = auto (not acc) L
        | auto true (x :: L) = x :: auto true L
        | auto false (_ :: L) = auto false L
   in String.implode (auto true (String.explode msg))
  end

(** Types **)

datatype message_type = NORMAL | TRACING | WARNING
type message = message_type * string
type flags = {
        is_toplevel: bool,
        is_theory  : bool,
        is_proof   : bool,
        is_skipped_proof: bool
}
type command_output = {
        command_name : string,
        message : message list, (*text printed in Isabelle's output panel*)
        output  : Latex.text option, (*text, section, and other latex commands*)
        flags   : flags,
        level   : int,
        state   : string,
        errors  : string list
}
type command_outputs = {
        outputs: command_output list,
        error : string option
}

(** Worker ID **)

type Worker_ID = int
val Worker_ID = Thread_Data.var () : (Worker_ID * theory) Thread_Data.var;

fun the_current_worker_ID () = Option.map fst (Thread_Data.get Worker_ID)

(** Message **)

val message_buffer : message list Inttab.table Synchronized.var
  = Synchronized.var "REPL.message_buffer" Inttab.empty

fun get_and_clean_message' wid =
  Synchronized.change_result message_buffer (fn tab =>
    let val ret = the_default [] (Inttab.lookup tab wid)
     in (rev ret, Inttab.update (wid, []) tab)
    end )

fun get_and_clean_message () =
  case Thread_Data.get Worker_ID
    of SOME (id, _) => get_and_clean_message' id
     | NONE => []

fun init_printers () =
  let fun output_fn typ fallback = (fn ms =>
            case Thread_Data.get Worker_ID
              of SOME (id, _) =>
                    Synchronized.change message_buffer
                        (Inttab.map_entry id (fn L => (typ, trim_makrup (implode ms)) :: L))
               | NONE => fallback ms )
   in Private_Output.writeln_fn := output_fn NORMAL  (!Private_Output.writeln_fn)
    ; Private_Output.tracing_fn := output_fn TRACING (!Private_Output.tracing_fn)
    ; Private_Output.warning_fn := output_fn WARNING (!Private_Output.warning_fn)
  end

val _ = init_printers ()

(** RE **)

type counter = int
val state = Thread_Data.var () : (Toplevel.state * counter) Thread_Data.var

fun RE source : command_outputs =
  case Thread_Data.get state
    of NONE          => {outputs=[], error=SOME "INTERNAL ERROR: state lost"}
     | SOME (s0,cnt) =>
  case Thread_Data.get Worker_ID
    of NONE          => {outputs=[], error=SOME "INTERNAL ERROR: worker ID lost"}
     | SOME (wid, thy00) =>
  let val thy = Toplevel.theory_of s0
                handle Toplevel.UNDEF => thy00
      val pos = Position.make {
                  line=0, offset=0, end_offset=0, props={label="", file="#REPL", id=string_of_int cnt}}
      val trs = Outer_Syntax.parse_text thy (K thy) pos source
             |> filter_out Toplevel.is_ignored

      val trim_err = map (#2 o #1)
      fun catch_state err tr s : command_output = {
              command_name = Toplevel.name_of tr,
              message = get_and_clean_message' wid,
              output  = Toplevel.output_of s,
              flags   = {
                    is_toplevel = Toplevel.is_toplevel s,
                    is_theory   = Toplevel.is_theory s,
                    is_proof    = Toplevel.is_proof s,
                    is_skipped_proof = Toplevel.is_skipped_proof s
                },
              level   = Toplevel.level s,
              state   = trim_makrup (Toplevel.string_of_state s),
              errors  = trim_err err
          }

      fun err_state err tr s : command_output = {
              command_name = Toplevel.name_of tr,
              message = [],
              output  = NONE,
              flags   = {
                    is_toplevel = Toplevel.is_toplevel s,
                    is_theory   = Toplevel.is_theory s,
                    is_proof    = Toplevel.is_proof s,
                    is_skipped_proof = Toplevel.is_skipped_proof s
                },
              level   = Toplevel.level s,
              state   = "",
              errors  = trim_err err
          }

      fun mk_command_outputs a b = {outputs=rev a, error=b} : command_outputs
      
      fun loop ret [] s = (mk_command_outputs ret NONE, s)
        | loop ret (tr::trs) s =
            case Toplevel.command_errors true tr s
              of (err, NONE)    =>
                    (mk_command_outputs (err_state err tr s::ret)
                                        (SOME "INTERNAL ERROR: state lost"), s0)
               | (err, SOME s') =>
                    loop ((catch_state err tr s')::ret) trs s'

      val (ret, s') = loop [] trs s0

   in Thread_Data.put state (SOME (s', cnt+1))
    ; ret
  end

fun init_repler thy =
  let val id = serial()
      val thy0 = (case thy
                    of SOME some => some
                     | NONE =>
                 (case Context.get_generic_context ()
                    of SOME some => Context.theory_of some
                     | NONE => Thy_Info.get_theory "Main"))
              |> Config.put_global Printer.show_markup false
   in Thread_Data.put Worker_ID (SOME (id, thy0))
    ; Synchronized.change message_buffer (Inttab.update_new (id, []))
    ; Thread_Data.put state (SOME (Toplevel.make_state thy, 0))
  end

end

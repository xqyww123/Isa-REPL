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
        output: message list,      (*text printed in Isabelle's output panel*)
        latex : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        errors : string list
}
type command_outputs = {
        outputs: command_output list option,
        error : string option
}

exception REPL_fail of string

type Session_ID = int
val init_repler : Session_ID -> theory option -> unit
val RE : {base_dir: Path.T, thy_qualifier: string} -> string -> command_outputs
val lex_commands : {base_dir: Path.T, thy_qualifier: string} -> string -> string list
val set_trace : bool -> unit

val the_current_worker_ID  : unit -> Session_ID option
val get_and_clean_message' : Session_ID -> message list
val get_and_clean_message  : unit -> message list

val trim_makrup : string -> string

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
        output  : message list, (*text printed in Isabelle's output panel*)
        latex   : Latex.text option, (*text, section, and other latex commands*)
        flags   : flags,
        level   : int,
        state   : string,
        errors  : string list
}
type command_outputs = {
        outputs: command_output list option,
        error : string option
}

(** Worker ID **)

type Session_ID = int
val Session_ID = Thread_Data.var () : Session_ID Thread_Data.var;

fun the_current_worker_ID () = Thread_Data.get Session_ID

(** Message **)

val message_buffer : message list Inttab.table Synchronized.var
  = Synchronized.var "REPL.message_buffer" Inttab.empty

fun get_and_clean_message' wid =
  Synchronized.change_result message_buffer (fn tab =>
    let val ret = the_default [] (Inttab.lookup tab wid)
     in (rev ret, Inttab.update (wid, []) tab)
    end )

fun get_and_clean_message () =
  case Thread_Data.get Session_ID
    of SOME id => get_and_clean_message' id
     | NONE => []

fun init_printers () =
  let fun output_fn typ fallback = (fn ms =>
            case Thread_Data.get Session_ID
              of SOME id =>
                    Synchronized.change message_buffer
                        (Inttab.map_entry id (fn L => (typ, trim_makrup (implode ms)) :: L))
               | NONE => fallback ms )
   in Private_Output.writeln_fn := output_fn NORMAL  (!Private_Output.writeln_fn)
    ; Private_Output.tracing_fn := output_fn TRACING (!Private_Output.tracing_fn)
    ; Private_Output.warning_fn := output_fn WARNING (!Private_Output.warning_fn)
  end

val _ = init_printers ()

(*val _ = Multithreading.parallel_proofs := 0 (*TODO: disable me!*)*)

(** RE **)

type counter = int
type trace = bool
val state = Thread_Data.var () : (Toplevel.state * counter * trace) Thread_Data.var

val Pure = Theory.get_pure ()
val pure_keywords = Thy_Header.get_keywords Pure

val evaluated_theories = Thread_Data.var () : theory Symtab.table Thread_Data.var

exception REPL_fail of string

fun is_theory_tok tok = Token.is_kind Token.Command tok andalso Token.content_of tok = "theory"

fun init_thy ignore_imports {base_dir, thy_qualifier} wid source =
  let val toks = Token.tokenize pure_keywords {strict = false} source
      val i = find_index is_theory_tok toks
   in if i = ~1
   then NONE
   else let
      val header_toks = List.drop (toks, i)
      val header = Thy_Header.read_tokens (Token.pos_of (hd header_toks)) header_toks

      fun qualify_name {name,imports,keywords} =
            {name=apfst (Long_Name.qualify ("REPL" ^ string_of_int wid)) name, imports=imports, keywords=keywords}
      val header = qualify_name header

      (* init theory *)
      val imports = #imports header
      val evaluated_theories = the_default Symtab.empty (Thread_Data.get evaluated_theories)
      fun parse import =
        let val can_load = Execution.is_running Document_ID.none
            fun load can_load import =
              case Symtab.lookup evaluated_theories import
                of SOME thy => thy
                 | NONE     => (
              case Thy_Info.lookup_theory import
                of SOME thy => thy
                 | NONE     => (
               if Long_Name.is_qualified import
               then if can_load
               then ((Thy_Info.use_thy import
                      handle ERROR _ => raise REPL_fail ("Bad theory import " ^ import));
                     load false import)
               else raise REPL_fail ("Bad theory import " ^ import)
               else load can_load (Long_Name.qualify thy_qualifier import)
              ))
         in load can_load import
        end
      val parents =
            if ignore_imports then []
            else imports |> map (fn (import, _ (*pos*)) => parse import)
      val parents =
            if null parents then [Pure] else parents
   in Resources.begin_theory base_dir header parents
   |> Config.put_global Printer.show_markup false
   |> SOME
  end
  end

fun get_thy cfg wid state source = (
      if can Toplevel.theory_of state <> Toplevel.is_toplevel state then ()
      else error "BUG: K/aPbPakSCOMOSqoevPh+g"
    ; case try Toplevel.theory_of state
          of SOME thy => thy
           | NONE => the_default Pure (init_thy false cfg wid source ))

(* fun split_commands src *)

fun parse_text' thy init text =
     Token.tokenize (Thy_Header.get_keywords thy) {strict = false} text
  |> Outer_Syntax.parse_spans
  |> map (Command_Span.content #> Outer_Syntax.parse_span thy init);

fun lex_split drop_first drop_if_no_meet kws P source =
  let val toks = Token.tokenize kws {strict = false} source
      val d = the (Position.offset_of (Token.pos_of (hd toks)))
      fun split _ met (_,ret,src) [] =
            rev (if drop_if_no_meet andalso not met then ret else src::ret)
        | split drop_first met (m,ret,src) (x :: xs) =
            if P x
            then let val m' = the (Position.offset_of (Token.pos_of x)) - d
                     val n = m' - m
                  in if n = 0 orelse drop_first
                  then split false true (m', ret, drop n src) xs
                  else split false true (m', take n src::ret, drop n src) xs
                 end
            else split drop_first met (m,ret, src) xs
   in split drop_first false (0,[],source) toks
  end

val split_thy_headers = lex_split false false pure_keywords is_theory_tok

fun parse_text cfg wid state source =
  let val thy = get_thy cfg wid state source
   in parse_text' thy (K thy) source
   |> filter_out Toplevel.is_ignored
  end

fun set_trace v =
  case Thread_Data.get state
    of NONE => raise REPL_fail "INTERNAL ERROR: state lost"
     | SOME (s,c,_) => Thread_Data.put state (SOME (s, c, v))

fun RE cfg source : command_outputs =
  case Thread_Data.get state
    of NONE                => {outputs=NONE, error=SOME "INTERNAL ERROR: state lost"}
     | SOME (s0,cnt,trace) =>
  case Thread_Data.get Session_ID
    of NONE     => {outputs=NONE, error=SOME "INTERNAL ERROR: worker ID lost"}
     | SOME wid =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=string_of_int cnt}}
      val srcs = Symbol_Pos.explode (source, pos)
              |> split_thy_headers

      val trim_err = map (trim_makrup o #2 o #1)
      fun catch_state err tr s : command_output = {
              command_name = Toplevel.name_of tr,
              output  = get_and_clean_message' wid,
              latex   = Toplevel.output_of s,
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
              output  = [],
              latex   = NONE,
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

      fun mk_command_outputs a b = {outputs = if trace then SOME (rev a) else NONE, error=b} : command_outputs
            
      fun loop ret [] [] s = (mk_command_outputs ret NONE, s)
        | loop ret [] (src::srcs) s = loop ret (parse_text cfg wid s src) srcs s
        | loop ret (tr::trs) srcs s =
            case Toplevel.command_errors true tr s
              of (err, NONE)    =>
                    (mk_command_outputs (if trace then err_state err tr s::ret else [])
                                        (SOME "Some error happens"), s0)
               | (err, SOME s') =>
                let val _ = if Toplevel.is_end_theory s'
                            then let
                              val thys = the_default Symtab.empty (Thread_Data.get evaluated_theories)
                              val thy  = Toplevel.end_theory pos s'
                              val thys'= Symtab.update_new (Context.theory_name {long=false} thy, thy) thys
                              in Thread_Data.put evaluated_theories (SOME thys')
                             end
                            else ()
                 in loop (if trace then (catch_state err tr s')::ret else []) trs srcs s'
                end

      val (ret, s') = loop [] [] srcs s0

   in Thread_Data.put state (SOME (s', cnt+1, trace))
    ; ret
  end
  handle REPL_fail E => {outputs = NONE, error=SOME E}

fun init_repler id thy =
  let 
   in Thread_Data.put Session_ID (SOME id)
    ; Synchronized.change message_buffer (Inttab.update_new (id, []))
    ; Thread_Data.put state (SOME (Toplevel.make_state thy, 0, true))
  end



(** Lex commands **)


fun split_commands cfg wid state source =
  let val thy = get_thy cfg wid state source
      val kws = Thy_Header.get_keywords thy
   in lex_split true true kws (Token.is_kind Token.Command) source
  end

fun lex_commands cfg source =
  case Thread_Data.get state
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s0,cnt,_) =>
  case Thread_Data.get Session_ID
    of NONE     => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME wid =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=string_of_int cnt}}
      fun parse [] = []
        | parse (src::srcs) =
        let val thy = case init_thy true cfg wid src
                        of SOME thy => thy
                         | NONE => the_default Pure (try Toplevel.theory_of s0)
            val kws = Thy_Header.get_keywords thy
            val ret = lex_split true true kws (Token.is_kind Token.Command) src

            val thys = the_default Symtab.empty (Thread_Data.get evaluated_theories)
            val thys'= Symtab.update_new (Context.theory_name {long=false} thy, thy) thys
         in map (Symbol_Pos.implode) ret
         :: Thread_Data.setmp evaluated_theories (SOME thys') parse srcs
        end
   in Symbol_Pos.explode (source, pos)
   |> split_thy_headers
   |> parse
   |> flat
  end

end

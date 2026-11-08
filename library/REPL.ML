signature REPL = sig

datatype message_type = NORMAL | TRACING | WARNING
type message = message_type * string

type cfg = { thy_qualifier : string,
             file : string option,
             position_label : string option,
             additional_libs : string list,
             configs: (string * string) list,
             import_dir : Path.T option,
             single_cmd_timeout: Time.time option,
             attributes : string list,
             base_dir: Path.T,
             write_thy: bool }

type collector = cfg
              -> {current_command: Command_Span.span,
                  state: Toplevel.state, (*the state after executing the current command*)
                  remaining: (Toplevel.transition * Command_Span.span) list
                                         (*the remaining commands within the same theory file*)}
              -> MessagePackBinIO.Pack.raw_packer option *
                 Toplevel.state option
type plugin_name = string
type plugin  = plugin_name * collector

type flags = {
        is_toplevel: bool,
        is_theory  : bool,
        is_proof   : bool,
        has_goal   : bool
}
type command_output = {
        command : string,
        output: message list,      (*text printed in Isabelle's output panel*)
        latex : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * MessagePackBinIO.Pack.raw_packer) list,
        errors : string list,
        range   : Position.T * Position.T
}
type command_outputs = {
        outputs: command_output list option,
        error : string option
}

val collect_erros : command_outputs -> string list

exception REPL_fail of string

type Session_ID = int
   (*initialize the current thread as a repl worker*)
val init_repler : theory option (*Initial theory*) -> Session_ID
val RE : cfg -> string -> command_outputs
val declare : string list (*attributes*) -> unit
val lex_commands : cfg -> string -> (Position.T * string) list
val fast_lex : string -> (Position.T * string) list

val set_trace : bool -> unit
    (*recording switch: whether theories evaluated on this connection are recorded
      into the connection's theory table; it has nothing to do with loaded theories*)
val set_register_thy : bool -> unit
val thy_loader : Path.T option -> string -> string list -> theory list

(* Plugin *)

val check_plugin : plugin_name -> collector option
val register_plugin : plugin -> unit
val delete_plugin : plugin_name -> unit

(* Message *)

val the_current_worker_ID  : unit -> Session_ID option
val get_and_clean_message' : Session_ID -> message list
val get_and_clean_message  : unit -> message list


(* State Rollback*)

type state_history = (string * Toplevel.state) list
val record_state : string -> unit
val record_state_global : string -> Toplevel.state Symtab.table Synchronized.var -> unit
val remove_state : string -> unit
val clean_state : unit -> unit
val rollback_state : cfg -> string -> command_output
val rollback_state_global : cfg -> string ->
        Toplevel.state Symtab.table Synchronized.var ->
          command_output
val list_states  : unit -> state_history
val list_states' : cfg -> unit -> (string (*name*) * command_output) list

(* Parse *)

val parse_term    : Toplevel.state -> string -> Proof.context * term
val retrieve_fact : Toplevel.state -> string -> Proof.context * thm list

(* Tools *)

val trim_makrup  : string -> string


val sledgehammer : Toplevel.state -> int (*timeout in seconds*) -> string

val premise_selection_each_goal : Toplevel.state -> Sledgehammer_Prover.params ->
      Sledgehammer_Fact.fact_override ->
        int -> (string * Sledgehammer_Fact.fact list) list list
val premise_selection_ultimate_goal : Toplevel.state -> Sledgehammer_Prover.params ->
      Sledgehammer_Fact.fact_override ->
        int -> (string * Sledgehammer_Fact.fact list) list
val premise_selection_leading_goal : Toplevel.state -> Sledgehammer_Prover.params ->
      Sledgehammer_Fact.fact_override ->
        int -> (string * Sledgehammer_Fact.fact list) list

(* Proof Context *)

type context = {
  local_facts: (string * thm list) list,
  assumptions: thm list,
  bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
  fixed_terms: typ Vartab.table * sort Vartab.table,
  goals      : cterm list
}

val get_toplevel_state : unit -> Toplevel.state
  (*a state query: run on the current state, under that state's theory options*)
val with_current_state : (Toplevel.state -> 'a) -> 'a
val get_context : Toplevel.state -> context
val get_ctxt : Toplevel.state -> Proof.context

val update_toplevel_state : (Toplevel.state -> Toplevel.state) -> unit

(*Auxiliary*)

val disable_output : unit -> unit

val origin_writeln : string list -> unit
val origin_tracing : string list -> unit
val origin_warning : string list -> unit

val path_of_the_theory : cfg -> string -> Path.T
val parse_thy_header : cfg -> string -> Thy_Header.header

(* Library Control *)

val add_evaluated_theory : theory -> unit
val add_global_theory : theory -> unit
val clear_evaluated_theories : bool -> unit

(* Internal *)

val split_thy_headers : Symbol_Pos.T list -> Symbol_Pos.T list list
val pure_keywords : Keyword.keywords

val init_printers : unit -> unit

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
        has_goal   : bool
}

type cfg = { thy_qualifier : string,
             file : string option,
             position_label : string option,
             additional_libs : string list,
             configs: (string * string) list,
             import_dir : Path.T option,
             single_cmd_timeout: Time.time option,
             attributes : string list,
             base_dir: Path.T,
             write_thy: bool }

type collector = cfg
              -> {current_command: Command_Span.span,
                  state: Toplevel.state, (*the state after executing the current command*)
                  remaining: (Toplevel.transition * Command_Span.span) list
                                         (*the remaining code within the same theory*)}
              -> MessagePackBinIO.Pack.raw_packer option *
                 Toplevel.state option
type plugin_name = string
type plugin  = plugin_name * collector
type plugins = plugin list

type command_output = {
        command : string,
        output  : message list, (*text printed in Isabelle's output panel*)
        latex   : Latex.text option, (*text, section, and other latex commands*)
        flags   : flags,
        level   : int,
        state   : string,
        plugin_output: (plugin_name * MessagePackBinIO.Pack.raw_packer) list,
        errors  : string list,
        range   : Position.T * Position.T
}
type command_outputs = {
        outputs: command_output list option,
        error : string option
}

fun collect_erros {outputs, error} =
      maps #errors (these outputs) @ the_list error


(** Plugin **)

fun run_plugins cfg (plugins : plugins) (current,remaining,s) =
  let fun loop ret [] s = (ret, s)
        | loop ret ((name,collector)::plugins) s =
        case PIDE_Loader.with_theory_options (fn s => collector cfg
                           {current_command = current,
                            state = s,
                            remaining = remaining}) s
          of (SOME out, SOME s') => loop ((name,out)::ret) plugins s'
           | (SOME out, NONE   ) => loop ((name,out)::ret) plugins s
           | (NONE    , SOME s') => loop ret plugins s'
           | (NONE    , NONE   ) => loop ret plugins s
   in loop [] plugins s
  end

val add_plugin : (plugin -> plugins -> plugins) = AList.update (op =)
val remove_plugin : (string -> plugins -> plugins) = AList.delete (op =)

(** Worker ID **)

type Session_ID = int
val Session_ID = Thread_Data.var () : (Session_ID * plugins) Thread_Data.var

fun the_current_worker_ID () = Option.map #1 (Thread_Data.get Session_ID)

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
    of SOME (id, _) => get_and_clean_message' id
     | NONE => []

val printer_inited = Synchronized.var "Isa-REPL.printer_inited" false

fun init_printers () =
  Synchronized.change printer_inited (
    fn false =>
      let fun output_fn typ fallback = (fn ms =>
                case Thread_Data.get Session_ID
                  of SOME (id, _) =>
                        Synchronized.change message_buffer
                            (Inttab.map_entry id (fn L => (typ, trim_makrup (implode ms)) :: L))
                   | NONE => fallback ms )
       in Private_Output.writeln_fn := output_fn NORMAL  (!Private_Output.writeln_fn)
        ; Private_Output.tracing_fn := output_fn TRACING (!Private_Output.tracing_fn)
        ; Private_Output.warning_fn := output_fn WARNING (!Private_Output.warning_fn)
        ; true
      end
      | _ => true)


val (origin_writeln, origin_tracing, origin_warning) =
    (!Private_Output.writeln_fn, !Private_Output.tracing_fn, !Private_Output.warning_fn)
(* val _ = init_printers () *)

(* The mute applies to the REPL world only.  It wraps 11 of the 13 Private_Output refs: a
   message carrying a document exec id (PIDE_Loader.is_document_message) belongs to a theory
   the PIDE document loads -- PIDE reports its progress and errors through these channels --
   and passes; every other message is dropped.  system_message_fn (the startup-failure
   diagnostic channel) and protocol_message_fn (protocol traffic the Scala peer must answer)
   stay unwrapped.  Recount 11 + 2 = 13 on a distribution bump. *)
fun disable_output () =
  let
    fun mute r =
      let val f = !r
      in r := (fn x => if PIDE_Loader.is_document_message [] then f x else ()) end
    val result = !Private_Output.result_fn
  in
    mute Private_Output.writeln_fn;
    mute Private_Output.writeln_urgent_fn;
    mute Private_Output.state_fn;
    mute Private_Output.information_fn;
    mute Private_Output.tracing_fn;
    mute Private_Output.warning_fn;
    mute Private_Output.legacy_fn;
    mute Private_Output.error_message_fn;
    mute Private_Output.status_fn;
    mute Private_Output.report_fn;
    Private_Output.result_fn :=
      (fn props => fn s => if PIDE_Loader.is_document_message props then result props s else ())
  end

(* val _ = Multithreading.parallel_proofs := 0 (*TODO: disable me!*) *)

(** State Rollback **)

type state_history = (string * Toplevel.state) list

(** RE **)

type counter = int
type trace = bool
type record_theory = bool
val state = Thread_Data.var () : (Toplevel.state * counter * (trace * record_theory) * state_history) Thread_Data.var

val Pure = Theory.get_pure ()
val pure_keywords = Thy_Header.get_keywords Pure

val evaluated_theories = Thread_Data.var ()
val global_theories = Synchronized.var "global_theories" Symtab.empty

exception REPL_fail of string

fun is_theory_tok tok = Token.is_kind Token.Command tok andalso Token.content_of tok = "theory"

fun evaluated_table () = the_default Symtab.empty (Thread_Data.get evaluated_theories)

(* By name: the connection's table, the shared table, then the heap and the theories the
   PIDE document loaded.  Never used to decide whether an import is loaded. *)
fun lookup_theory name =
  get_first (fn look => look name)
    [Symtab.lookup (evaluated_table ()),
     Symtab.lookup (Synchronized.value global_theories),
     PIDE_Loader.lookup_theory]

(* Imports: the REPL tables answer the theories they hold; all the others go to the loader
   in one call.  Answers stay in request order: \005load replies by position, and the
   order of parents changes the theory. *)
fun thy_loader import_dir thy_qualifier imports =
  let
    val dir = the_default Path.root import_dir
    fun repl_table s =
      let val name = #theory_name (Resources.import_name thy_qualifier dir s)
      in get_first (fn tab => Symtab.lookup tab name)
          [evaluated_table (), Synchronized.value global_theories]
      end
    val held = map repl_table imports
    val loaded =
      burrow_options (PIDE_Loader.use_theories thy_qualifier dir)
        (map2 (fn s => fn thy => if is_some thy then NONE else SOME s) imports held)
  in map2 (fn a => fn b => the (merge_options (a, b))) held loaded end

(* Recording a theory under its long name.  Before writing, drop every
   entry that is, or has among its ancestors, a theory of the same base
   name that is not this one: Context.begin_thy rejects two such theories
   in one ancestry with THEORY ("Duplicate theory name", ...) --
   eq_thy_consistent compares base names, not long names -- far from the
   cause. *)
fun insert_theory thy tab =
  let
    val key = Context.theory_name {long = true} thy
    val base = Context.theory_name {long = false} thy
    fun shadowed thy' =
      exists (fn a => Context.theory_name {long = false} a = base andalso not (Context.eq_thy (a, thy)))
        (thy' :: Context.ancestors_of thy')
    val stale = Symtab.fold (fn (k, thy') => shadowed thy' ? cons k) tab []
  in Symtab.update (key, thy) (fold Symtab.delete_safe stale tab) end

fun recorded_table thy = insert_theory thy (evaluated_table ())

fun add_evaluated_theory thy = Thread_Data.put evaluated_theories (SOME (recorded_table thy))

fun add_global_theory thy = Synchronized.change global_theories (insert_theory thy)

fun with_recorded_theory thy f = Thread_Data.setmp evaluated_theories (SOME (recorded_table thy)) f ()

fun clear_evaluated_theories also_global =
  (Thread_Data.put evaluated_theories (SOME Symtab.empty);
   if also_global then Synchronized.change global_theories (K Symtab.empty) else ())

val eq_symb = Token.make ((1,0), "=") Position.none |> fst
fun mk_idt s = Token.make ((2,0),s) Position.none |> fst

(* PIDE's init function for a command that must not begin a theory (document.ML:719) *)
fun illegal_init _ = error "Illegal theory header"

(* The theory a header in source begins, and the init function of its header command:
   PIDE_Loader.init_theory applies the header options and `condition`. *)
fun init_thy ignore_imports {thy_qualifier, base_dir, additional_libs, configs, import_dir, attributes,...} source =
  let val toks = Token.tokenize pure_keywords {strict = false} source
      val i = find_index is_theory_tok toks
   in if i = ~1
   then NONE
   else let
      val header_toks = List.drop (toks, i)
      val header = Thy_Header.read_tokens (Token.pos_of (hd header_toks)) header_toks
      val (name, pos) = #name header

      (* init theory *)
      (* PREPEND additional_libs (before the target's own imports): the injected
         libs (e.g. Minilang_AoA) become BASE ancestors that only add tools/
         certificate lineage, while the target theory's own imports come LAST so
         the target's own syntax/notation wins on any conflict. *)
      val imports = map (rpair Position.none) additional_libs
                  @ #imports header

      val parents =
            if ignore_imports then []
            else thy_loader import_dir thy_qualifier (map fst imports)
      val parents =
            if null parents then [Pure] else parents
      (* begin_theory reads only name, position and keywords (resources.ML:314-323) *)
      val thy_record : Resources.thy =
        {name = {node = "", master_dir = base_dir, theory = Long_Name.qualify thy_qualifier name},
         pos = pos, imports = [], options = [], keywords = #keywords header,
         condition_bad = (false, ""), errors = [], initiators = []}
   in Resources.begin_theory thy_record parents
   |> Config.put_global Printer.show_markup false
   |> Config.put_global Printer.show_type_emphasis false
   |> (fn thy =>
      let val ctxt = Proof_Context.init_global thy
          val keywords = Thy_Header.get_keywords thy
          val attrs = map (Attrib.attribute_cmd ctxt)
                          (map ( Input.string
                              #> Input.source_explode
                              #> Token.tokenize keywords {strict = true}
                              #> filter Token.is_proper
                               ) attributes)
       in Thm.theory_attributes attrs Drule.dummy_thm thy
       |> snd
      end)
   |> not (null configs) ? (fn thy =>
      let val toks = map (fn (k,v) =>
                [Token.make_string (k, Position.none),
                 eq_symb,
                 if Char.contains v #" " orelse Char.contains v #"\""
                 then Token.make_string (v, Position.none)
                 else mk_idt v]) configs
          val attrs = map (Attrib.attribute_cmd_global thy) toks
       in Thm.theory_attributes attrs Drule.dummy_thm thy
       |> snd
      end )
   |> (fn thy => SOME (thy, PIDE_Loader.init_theory (#options header) thy))
  end
  end

(* the theory to parse with, and the init function of a header command in the source *)
fun get_thy rm_thy cfg state source = (
      if can Toplevel.theory_of state <> Toplevel.is_toplevel state then ()
      else error "BUG: K/aPbPakSCOMOSqoevPh+g"
    ; case try Toplevel.theory_of state
          of SOME thy => (thy, illegal_init)
           | NONE =>
      case init_thy false cfg source
        of SOME (thy, init) => let
            val path = Path.append (Resources.master_directory thy)
                                   (Path.explode (Context.theory_name {long=false} thy ^ ".thy"))
             in if File.exists path andalso rm_thy then File.rm path else ()
              ; (thy, init)
            end
         | NONE => (Pure, illegal_init))

(* fun split_commands src *)

fun parse_text' thy init text =
  let val keywords = Thy_Header.get_keywords thy
   in Token.tokenize keywords {strict = false} text
   |> Outer_Syntax.parse_spans (Keyword.command_kind keywords)
   |> map (` (Command_Span.content #> Outer_Syntax.parse_span thy init))
   |> filter_out (Toplevel.is_ignored o fst)
  end

fun lex_split drop_first drop_if_no_meet kws ATTACH P source =
  let val toks = Token.tokenize kws {strict = false} source
      val d = the (Position.offset_of (Token.pos_of (hd toks)))
      fun split _ met (_,_,ret,src) [] =
            rev (if drop_if_no_meet andalso not met then ret else src::ret)
        | split drop_first met (m,h0,ret,src) (x :: xs) =
            let val h = the_default x h0
             in if P x
            then let val m' = the (Position.offset_of (Token.pos_of h)) - d
                     val n = m' - m
                  in if n = 0 orelse drop_first
                  then split false true (m', NONE, ret, drop n src) xs
                  else split false true (m', NONE, take n src::ret, drop n src) xs
                 end
            else if ATTACH x
            then split drop_first met (m, SOME h, ret, src) xs
            else if Token.is_space x
            then split drop_first met (m, h0, ret, src) xs
            else split drop_first met (m, NONE, ret, src) xs
            end
   in split drop_first false (0,NONE,[],source) toks
  end

val split_thy_headers = lex_split false false pure_keywords Token.is_command_modifier is_theory_tok

(* write_thy is false in every cfg since D10 (nothing sets it true), so the
   File.append below and get_thy's File.rm are unreachable; the disk write-back
   mechanism is kept but dead, see THEORY_LOADER_LAYERING_PLAN §7.5. *)
fun parse_text (cfg:cfg) state source =
  let val write_thy = #write_thy cfg
      val (thy, init) = get_thy write_thy cfg state source
   in if write_thy andalso not (pointer_eq (Pure, thy))
         andalso Path.expand (Resources.master_directory thy) = Path.expand (#base_dir cfg)
    then File.append (Path.append (Resources.master_directory thy)
                                  (Path.explode (Context.theory_name {long=false} thy ^ ".thy")))
                     (Symbol_Pos.content source)
    else ()
    ; parse_text' thy init source
  end

fun set_trace v =
  case Thread_Data.get state
    of NONE => raise REPL_fail "INTERNAL ERROR: state lost"
     | SOME (s,c,(_,rt),H) => Thread_Data.put state (SOME (s, c, (v, rt), H))

fun set_register_thy v =
  case Thread_Data.get state
    of NONE => raise REPL_fail "INTERNAL ERROR: state lost"
     | SOME (s,c,(tr,_),H) => Thread_Data.put state (SOME (s, c, (tr, v), H))

val trim_err = map (trim_makrup o #2 o #1)
fun catch_state' wid plugin_output err command range s : command_output =
  PIDE_Loader.with_theory_options (fn s => {
        command = command,
        output  = get_and_clean_message' wid,
        latex   = NONE (*Toplevel.output_of s*),
        flags   = {
              is_toplevel = Toplevel.is_toplevel s,
              is_theory   = Toplevel.is_theory s,
              is_proof    = Toplevel.is_proof s,
              has_goal    = Toplevel.is_proof s andalso
                            can Proof.raw_goal (Toplevel.proof_of s) andalso
                            not (Thm.no_prems (#goal (Proof.raw_goal (Toplevel.proof_of s))))
          },
        level   = Toplevel.proof_level s,
        state   = trim_makrup (Toplevel.pretty_state s |> Pretty.chunks |> Pretty.string_of),
        plugin_output = plugin_output,
        errors  = trim_err err,
        range   = range
    }) s

fun apply_single_cmd_timeout (Command_Span.Span (Command_Span.Command_Span {name, ...}, toks)) =
      let val bad = ["auto_sledgehammer", "sledgehammer"]
       in not (member (op =) bad name) andalso
          not (exists (fn tok => member (op =) bad (Token.content_of tok)) toks)
      end
  | apply_single_cmd_timeout _ = true

fun last [] = error "no last"
  | last [x] = x
  | last (_ :: L) = last L

fun end_pos_of shift pos =
  Position.make {
    line = the_default 0 (Position.line_of pos),
    offset = the_default 1 (Position.end_offset_of pos) - 1 + shift,
    end_offset = the_default 1 (Position.end_offset_of pos) + shift,
    props= { label = the_default "" (Position.label_of pos),
             file = the_default "" (Position.file_of pos),
             id = the_default "" (Position.id_of pos) }
  }

fun print_toks [] = []
  | print_toks toks =
  let open Token Position
      fun assmble _ [] = []
        | assmble NONE (tok :: toks) =
            let val pos  = pos_of tok
             in case (line_of pos, end_offset_of pos)
             of (SOME line, SOME ofst') =>
                     " " :: unparse tok :: assmble (SOME (line, ofst')) toks
              | _ => " " :: unparse tok :: assmble NONE toks
            end
        | assmble (SOME (line0, ofst0)) (tok :: toks) =
            let val pos  = pos_of tok
             in case (line_of pos, offset_of pos, end_offset_of pos)
             of (SOME line, SOME ofst, SOME ofst') =>
                  if line = line0 andalso ofst0 = ofst
                  then unparse tok :: assmble (SOME (line, ofst')) toks
                  else " " :: unparse tok :: assmble (SOME (line, ofst')) toks
              | _ => " " :: unparse tok :: assmble NONE toks
            end
   in tl (assmble NONE toks)
  end

fun RE (cfg:cfg) source : command_outputs =
  case Thread_Data.get state
    of NONE                  => {outputs=NONE, error=SOME "INTERNAL ERROR: state lost"}
     | SOME (s0,cnt,(trace, record_theory'),H) =>
  case Thread_Data.get Session_ID
    of NONE                => {outputs=NONE, error=SOME "INTERNAL ERROR: worker ID lost"}
     | SOME (wid, plugins) =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1,
                  props= { label = the_default "" (#position_label cfg),
                           file = the_default "#REPL" (#file cfg),
                           id="" }
                }
      val srcs = Symbol_Pos.explode (source, pos)
              |> split_thy_headers

      fun range_of (Command_Span.Span (_, toks)) =
          case toks of [] => (Position.none, Position.none)
                     | _ => (Token.pos_of (hd toks), end_pos_of 0 (Token.pos_of (last toks)))
      fun cmd_expr_of (Command_Span.Span (_, toks)) = print_toks toks |> String.concat
      fun catch_state plugin_output err cmd s : command_output
        = catch_state' wid plugin_output err (cmd_expr_of cmd) (range_of cmd) s

      fun err_state err cmd s : command_output = {
              command = cmd_expr_of cmd,
              output  = [],
              latex   = NONE,
              flags   = {
                    is_toplevel = Toplevel.is_toplevel s,
                    is_theory   = Toplevel.is_theory s,
                    is_proof    = Toplevel.is_proof s,
                    has_goal    = Toplevel.is_proof s andalso
                                  can Proof.raw_goal (Toplevel.proof_of s) andalso
                                  not (Thm.no_prems (#goal (Proof.raw_goal (Toplevel.proof_of s))))
                },
              level   = Toplevel.proof_level s,
              state   = "",
              plugin_output = [],
              errors  = trim_err err,
              range   = range_of cmd
          }

      fun mk_command_outputs a b = {outputs = if trace then SOME (rev a) else NONE, error=b} : command_outputs

      fun loop ret _ [] [] s = (mk_command_outputs ret NONE, s)
        | loop ret errs [] (src::srcs) s =
            loop ret errs (parse_text cfg s src) srcs s
        | loop ret errs ((tr,current_cmd)::trs) srcs s =
            let val (tr,current_cmd) =
                  if Toplevel.is_malformed tr
                  then let val thy = Toplevel.theory_of s
                        in Command_Span.content current_cmd
                        |> Outer_Syntax.parse_span thy illegal_init
                        |> rpair current_cmd
                       end
                  else (tr,current_cmd)
                (* under the theory options of the state it starts from *)
                val step = PIDE_Loader.with_theory_options (Toplevel.command_errors tr)
             in case (case #single_cmd_timeout cfg
                    of NONE => step s
                     | SOME time =>
                          if apply_single_cmd_timeout current_cmd
                          then Timeout.apply time step s
                               handle Timeout.TIMEOUT t =>
                                  ([((serial(), "Timeout after " ^ Time.toString t ^ "s"), NONE)], NONE)
                          else step s )
              of (err, NONE)    =>
                  let val Er = case trim_err err @ errs
                                 of [] => "Some error happens. Details may be given in the field `outputs.errors.` \
                                          \See the document for Python client's `boring_parse` method. "
                                  | Er => String.concatWith "\n\n" Er
                   in (mk_command_outputs (if trace then err_state err current_cmd s::ret else [])
                                          (SOME Er), s0)
                  end
               | (err, SOME s'0) =>
                let val (plugin_output, s') = run_plugins cfg plugins (current_cmd, trs, s'0)
                    val _ = if Toplevel.is_end_theory s' andalso record_theory'
                            then add_evaluated_theory (Toplevel.end_theory pos s')
                            else ()
                 in loop (if trace then (catch_state plugin_output err current_cmd s')::ret else [])
                         (trim_err err @ errs)
                         trs srcs s'
                end
            end

      val (ret, s') = loop [] [] [] srcs s0

   in Thread_Data.put state (SOME (s', cnt+1, (trace, record_theory'), H))
    ; ret
  end
  handle REPL_fail E => {outputs = NONE, error=SOME E}

val ID_counter = Counter.make ()

fun init_repler thy =
  let val id = ID_counter ()
   in Thread_Data.put Session_ID (SOME (id, []))
    ; Synchronized.change message_buffer (Inttab.update_new (id, []))
    ; Thread_Data.put state (SOME (Toplevel.make_state (Option.map Context.Theory thy), 0, (true, true), []))
    ; id
  end

fun declare attributes =
  case Thread_Data.get state
    of NONE => raise REPL_fail "INTERNAL ERROR: state lost"
     | SOME (s0,cnt,xx,H) =>
   let fun app ctxt0 =
        let val ctxt = Context.proof_of ctxt0
            val keywords = Thy_Header.get_keywords (Context.theory_of ctxt0)
            val attrs = map (Attrib.attribute_cmd ctxt)
                            (map ( Input.string
                                #> Input.source_explode
                                #> Token.tokenize keywords {strict = true}
                                #> filter Token.is_proper
                                 ) attributes)
         in Context.mapping (Thm.theory_attributes attrs Drule.dummy_thm #> snd)
                            (Thm.proof_attributes attrs Drule.dummy_thm #> snd)
                            ctxt0
        end
       val tr = if Toplevel.is_proof s0
                then Toplevel.proof (Proof.map_context (Context.proof_map app)) Toplevel.empty
                else if Toplevel.is_theory s0
                then Toplevel.theory (Context.theory_map app) Toplevel.empty
                else Toplevel.local_theory NONE NONE (Context.proof_map app) Toplevel.empty
       val s' = PIDE_Loader.with_theory_options (Toplevel.command_exception tr) s0
    in Thread_Data.put state (SOME (s',cnt,xx,H))
   end


(** Lex commands **)

(*
fun split_commands cfg wid state source =
  let val thy = get_thy cfg wid state source
      val kws = Thy_Header.get_keywords thy
   in lex_split true true kws (Token.is_kind Token.Command) source
  end
*)

fun lex_commands cfg source =
  case Thread_Data.get Session_ID
    of NONE         => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (_,_) =>
  case Thread_Data.get state
    of NONE              => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s0,cnt,_,_) =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=""}}
      fun parse [] = []
        | parse (src::srcs) =
        let val thy = case init_thy false cfg src
                        of SOME (thy, _) => thy  (*only the theory: no header command runs*)
                         | NONE =>
                            if null srcs
                            then raise REPL_fail ("fail to load the theory " ^ Path.implode (#base_dir cfg))
                            else the_default Pure (try Toplevel.theory_of s0)
            val kws = Thy_Header.get_keywords thy
            val ret = lex_split true true kws Token.is_command_modifier (Token.is_kind Token.Command) src

            fun pos_of [] = Position.none
              | pos_of (h :: _) = snd h
         in map (fn syms => (pos_of syms, Symbol_Pos.implode syms)) ret
         :: with_recorded_theory thy (fn () => parse srcs)
        end
   in Symbol_Pos.explode (source, pos)
   |> split_thy_headers
   |> parse
   |> flat
  end

(*without evaluating the target theory, it uses only known keywords from the Pure.thy.
  Thus it is fast and stateless but the result can be inaccurate.*)
fun fast_lex source =
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=""}}
      fun parse [] = []
        | parse (src::srcs) =
        let val ret = lex_split true true pure_keywords Token.is_command_modifier (Token.is_kind Token.Command) src
            fun pos_of [] = Position.none
              | pos_of (h :: _) = snd h
         in map (fn syms => (pos_of syms, Symbol_Pos.implode syms)) ret
         :: parse srcs
        end
   in Symbol_Pos.explode (source, pos)
   |> split_thy_headers
   |> parse
   |> flat
  end

(** Plugin II **)

fun check_plugin name =
  case Thread_Data.get Session_ID
    of NONE               => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (_, plugins) =>
        AList.lookup (op =) plugins name

fun register_plugin plugin =
  case Thread_Data.get Session_ID
    of NONE               => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (wid, plugins) =>
        Thread_Data.put Session_ID (SOME (wid, add_plugin plugin plugins))

fun delete_plugin name =
  case Thread_Data.get Session_ID
    of NONE               => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (wid, plugins) =>
        Thread_Data.put Session_ID (SOME (wid, remove_plugin name plugins))

(** State Rollback II **)

fun record_state name =
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,cnt,t,H) =>
     Thread_Data.put state (SOME (s, cnt, t, AList.update (op =) (name,s) H))

fun record_state_global name store =
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) =>
     Synchronized.change store (Symtab.update (name, s))

fun remove_state name =
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,cnt,t,H) =>
     Thread_Data.put state (SOME (s, cnt, t, AList.delete (op =) name H))

fun clean_state () =
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,cnt,t,_) =>
     Thread_Data.put state (SOME (s, cnt, t, []))


fun rollback_state cfg name =
  case Thread_Data.get Session_ID
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, plugins) =>
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,cnt,t,H) =>
  case AList.lookup (op =) H name
    of NONE => raise REPL_fail ("Historical state " ^ name ^ " is not found.")
     | SOME s' => let
       val (plugin_output, s'') =
            run_plugins cfg plugins (Command_Span.Span
                                        (Command_Span.Command_Span {name = "<rollback>", kind = "", pos = Position.none}, []),
                                     [],
                                     s')
    in Thread_Data.put state (SOME (s'', cnt, t, H))
     ; catch_state' wid plugin_output [] "" (Position.none, Position.none) s'
   end

fun rollback_state_global cfg name store =
  case Thread_Data.get Session_ID
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, plugins) =>
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,cnt,t,H) =>
  case Symtab.lookup (Synchronized.value store) name
    |> (fn NONE => AList.lookup (op =) H name
         | some => some)
    of NONE => raise REPL_fail ("Historical state " ^ name ^ " is not found.")
     | SOME s' => let
       val (plugin_output, s'') =
            run_plugins cfg plugins (Command_Span.Span
                                        (Command_Span.Command_Span {name = "<rollback>", kind = "", pos = Position.none}, []),
                                     [],
                                     s')
    in Thread_Data.put state (SOME (s'', cnt, t, H))
     ; catch_state' wid plugin_output [] "" (Position.none, Position.none) s'
   end

fun list_states () =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,_,_,H) => H

fun list_states' cfg () =
  case Thread_Data.get Session_ID
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, plugins) =>
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,_,_,H) => map (apsnd (fn s' =>
          catch_state' wid (#1 (
            run_plugins cfg plugins (Command_Span.Span
                                        (Command_Span.Command_Span {name = "<list>", kind = "", pos = Position.none}, []),
                                     [],
                                     s')
          )) [] "" (Position.none, Position.none) s'
       )) H

(** Parser **)

fun parse_term s term =
  case try Toplevel.context_of s
    of SOME ctxt => (ctxt, Syntax.read_term ctxt term)
     | NONE     => raise REPL_fail "Not in a theory context.\n\
            \You must evaluate at least a theory head (e.g., 'theory THY imports Main begin') to \
            \indicate the theory under which the term will be parsed."

fun retrieve_fact s name =
  case try Toplevel.context_of s
    of SOME ctxt =>
      let val keywords = Thy_Header.get_keywords (Proof_Context.theory_of ctxt)
          val thms = Parse.read_embedded ctxt keywords Parse.thms1 (Input.string name)
                  |> Attrib.eval_thms ctxt
       in (ctxt, thms)
      end
     | NONE     => raise REPL_fail "Not in a theory context.\n\
            \You must evaluate at least a theory head (e.g., 'theory THY imports Main begin') to \
            \indicate the theory under which the term will be parsed."

(** Sledgehammer **)

fun sledgehammer s timeout' = (
  case try Toplevel.proof_of s
    of SOME stat =>
       let val timeout = Time.fromSeconds timeout'
        in (if timeout' <= 0 then I else Timeout.apply_physical timeout) (fn () => let
           val ctxt = Proof.context_of stat
                   |> (if timeout' <= 0 then I
                       else Config.map Phi_Sledgehammer_Solver.sledgehammer_params
                                 (*no separator onto an empty config: the strict
                                   params parser rejects a dangling ", " tail*)
                                 (fn s => "timeout = " ^ string_of_int timeout' ^
                                          (if s = "" then "" else ", " ^ s)))
           val goal = Proof.goal stat |> #goal
           val (prf, _) =
                 Phi_Sledgehammer_Solver.auto
                   {improved = true, async_mode = Phi_Sledgehammer_Solver.Sync,
                    fact_override = Sledgehammer_Fact.no_fact_override,
                    proof_id = NONE,
                    timeout = NONE,      (*stays NONE: the physical Timeout.apply above is ours*)
                    read_store = NONE, write_store = NONE}
                   ctxt goal
                 (*Sync hands back a raw Auto_Fail; rendering it is ours to do, or
                   the client would receive "exception Auto_Fail raised".
                   Internal_Failure keeps its own payload.*)
                 handle Phi_Sledgehammer_Solver.Auto_Fail
                          (Phi_Sledgehammer_Solver.Internal_Failure msg) => error msg
                      | Phi_Sledgehammer_Solver.Auto_Fail _ =>
                          error (Phi_Sledgehammer_Solver.error_message ctxt goal)
        (*One of the two sanctioned joins: this call is always Sync, so
          the future is a Future.value and joining costs nothing -- and the proof
          text is exactly what we owe the REPL client.*)
        in snd (Future.join prf)
       end) ()
       end
     | NONE      => raise REPL_fail "Not in a proof context." )

fun gen_premise_selection select s param override number =
  (*number: how many facts do you want me to return*)
  case try Toplevel.proof_of s
    of SOME stat =>
       let val {context, facts, goal} = Proof.raw_goal stat
        in select param override number context facts goal
       end
     | NONE      => raise REPL_fail "Not in a proof context."


val premise_selection_each_goal = gen_premise_selection Premise_Selection.SH_select
val premise_selection_ultimate_goal = gen_premise_selection Premise_Selection.SH_select_ultimate_goal
val premise_selection_leading_goal = gen_premise_selection Premise_Selection.SH_select_leading_goal


(** get context **)

type context = {
  local_facts: (string * thm list) list,
  assumptions: thm list,
  bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
  fixed_terms: typ Vartab.table * sort Vartab.table,
  goals      : cterm list
}

fun get_toplevel_state () =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) => s

fun update_toplevel_state F =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,b,c,d) => Thread_Data.put state (SOME (F s, b, c, d))

(* A state query: the connection's current state, read once; the query's computation and its
   output run under that state's theory options (a print option is read when printing). *)
fun with_current_state f = PIDE_Loader.with_theory_options f (get_toplevel_state ())

fun get_context s =
     case (try Toplevel.context_of s, try Toplevel.proof_of s)
    of (SOME ctxt, prfstate) =>
      let
        val facts = Proof_Context.facts_of ctxt
        val props = map #1 (Facts.props facts)

        fun steal ctxt =
          let val lv = Local_Theory.level ctxt
              val ret = Unsynchronized.ref NONE
           in Local_Theory.map_contexts (fn i => fn X =>
                ((if i = lv - 1 then ret := SOME X else () ); X)) ctxt
            ; case !ret
                of SOME ret => ret
                 | NONE => error "BUG: REPL.get_context.steal"
          end
        val facts' = if can Local_Theory.assert ctxt
             then Proof_Context.facts_of (steal ctxt)
             else Global_Theory.facts_of (Proof_Context.theory_of ctxt)

        val local_facts =
          (if null props then [] else [("<unnamed>", props)]) @
          Facts.dest_static false [facts'] facts

        val assms = Assumption.all_prems_of ctxt

       in {local_facts = local_facts,
           assumptions = assms,
           bindings = Variable.binds_of ctxt,
           fixed_terms = Variable.constraints_of ctxt,
           goals = (case prfstate of NONE => []
                       | SOME s => Thm.cprems_of (#goal (Proof.goal s)) )}
      end
     | (NONE, _) => raise REPL_fail "Not in a proof context."

fun get_ctxt s =
  case try Toplevel.context_of s
    of SOME ctxt => ctxt
     | NONE => raise REPL_fail "Not in a proof context."

(** Auxiliary **)

val dot_path = Path.explode "."

fun path_of_the_theory (cfg : cfg) name =
  let
    val dir = the_default Path.root (#import_dir cfg)
    val {master_dir, theory_name, ...} = Resources.import_name (#thy_qualifier cfg) dir name
    fun path_of thy =
      Path.append (Resources.master_directory thy)
                  (Path.basic (Context.theory_name {long = false} thy ^ ".thy"))
    val candidate =
      (case lookup_theory theory_name of
        SOME thy => path_of thy
      | NONE =>
          if master_dir = dot_path
          then raise REPL_fail ("Fail to infer the path of the theory " ^ name)
          else Path.append master_dir (Path.basic (Long_Name.base_name theory_name ^ ".thy")))
  in
    if File.is_file candidate then candidate
    else raise REPL_fail ("Fail to infer the path of the theory " ^ name ^
                          " (no such file: " ^ Path.implode candidate ^ ")")
  end

fun parse_thy_header (cfg:cfg) text =
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1,
                  props= { label = the_default "" (#position_label cfg),
                           file = the_default "#REPL" (#file cfg),
                           id="" }
                }
      val symbs = Symbol_Pos.explode (text, pos)
      val toks = Token.tokenize pure_keywords {strict = false} symbs
      val {name, imports, options, keywords} = Thy_Header.read_tokens pos toks
   in Thy_Header.make (apfst (Long_Name.qualify (#thy_qualifier cfg)) name) imports options keywords
  end

end

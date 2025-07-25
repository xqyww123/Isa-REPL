signature REPL = sig

datatype message_type = NORMAL | TRACING | WARNING
type message = message_type * string

type cfg = { thy_qualifier : string,
             file : string option,
             position_label : string option,
             additional_libs : string list,
             import_dir : Path.T option,
             single_cmd_timeout: Time.time option,
             attributes : string list }

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
        command_name : string,
        output: message list,      (*text printed in Isabelle's output panel*)
        latex : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * MessagePackBinIO.Pack.raw_packer) list,
        errors : string list
}
type command_outputs = {
        outputs: command_output list option,
        error : string option
}

val collect_erros : command_outputs -> string list

exception REPL_fail of string

type Session_ID = int
   (*initialize the current thread as a repl worker*)
val init_repler : Path.T (*base_dir used to store outputs*)
               -> theory option (*Initial theory*) -> Session_ID
val RE : cfg -> string -> command_outputs
val declare : string list (*attributes*) -> unit
val lex_commands : cfg -> string -> (Position.T * string) list
val fast_lex : string -> (Position.T * string) list

val set_trace : bool -> unit
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

val parse_term    : string -> Proof.context * term
val retrieve_fact : string -> Proof.context * thm list

(* Tools *)

val trim_makrup  : string -> string
val sledgehammer : int (*timeout in seconds*) -> string

(* Proof Context *)

type context = {
  local_facts: (string * thm list) list,
  assumptions: thm list,
  bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
  fixed_terms: typ Vartab.table * sort Vartab.table,
  goals      : cterm list
}

val get_toplevel_state : unit -> Toplevel.state
val get_context : unit -> context
val get_ctxt : unit -> Proof.context

(*Auxiliary*)

val disable_output : unit -> unit

val origin_writeln : string list -> unit
val origin_tracing : string list -> unit
val origin_warning : string list -> unit

val path_of_the_theory : cfg -> string -> Path.T
val parse_thy_header : cfg -> string -> Thy_Header.header

(* Library Control *)

    (*additional imports that will be injected into every evaluation target*)
val evaluated_theories : theory Symtab.table Thread_Data.var
val add_evaluated_theories : string * theory -> unit
val add_global_theories : string * theory -> unit

(* Internal *)

val split_thy_headers : Symbol_Pos.T list -> Symbol_Pos.T list list
val pure_keywords : Keyword.keywords

(* Set base_dir *)
(*TODO: move this to cfg*)

val get_base_dir : unit -> Path.T
val set_base_dir : Path.T -> unit
val reset_base_dir : unit -> unit

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
             import_dir : Path.T option,
             single_cmd_timeout: Time.time option,
             attributes : string list }

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
        command_name : string,
        output  : message list, (*text printed in Isabelle's output panel*)
        latex   : Latex.text option, (*text, section, and other latex commands*)
        flags   : flags,
        level   : int,
        state   : string,
        plugin_output: (plugin_name * MessagePackBinIO.Pack.raw_packer) list,
        errors  : string list
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
        case collector cfg {current_command = current,
                            state = s,
                            remaining = remaining}
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
val Session_ID = Thread_Data.var () : (Session_ID * Path.T * Path.T * plugins) Thread_Data.var

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
    of SOME (id, _, _, _) => get_and_clean_message' id
     | NONE => []

fun init_printers () =
  let fun output_fn typ fallback = (fn ms =>
            case Thread_Data.get Session_ID
              of SOME (id, _, _, _) =>
                    Synchronized.change message_buffer
                        (Inttab.map_entry id (fn L => (typ, trim_makrup (implode ms)) :: L))
               | NONE => fallback ms )
   in Private_Output.writeln_fn := output_fn NORMAL  (!Private_Output.writeln_fn)
    ; Private_Output.tracing_fn := output_fn TRACING (!Private_Output.tracing_fn)
    ; Private_Output.warning_fn := output_fn WARNING (!Private_Output.warning_fn)
  end


val (origin_writeln, origin_tracing, origin_warning) =
    (!Private_Output.writeln_fn, !Private_Output.tracing_fn, !Private_Output.warning_fn)
val _ = init_printers ()

fun disable_output () = (
  Private_Output.writeln_fn := K () ;
  Private_Output.state_fn := K () ;
  Private_Output.information_fn := K () ;
  Private_Output.tracing_fn := K () ;
  Private_Output.warning_fn := K () ;
  Private_Output.legacy_fn := K () ;
  Private_Output.error_message_fn := K () ;
  Private_Output.status_fn := K () ;
  Private_Output.report_fn := K () ;
  Private_Output.result_fn := K (K ())
)

(*val _ = Multithreading.parallel_proofs := 0 (*TODO: disable me!*)*)

(** State Rollback **)

type state_history = (string * Toplevel.state) list

(** RE **)

type counter = int
type trace = bool
type register_theory = bool
val state = Thread_Data.var () : (Toplevel.state * counter * (trace * register_theory) * state_history) Thread_Data.var

val Pure = Theory.get_pure ()
val pure_keywords = Thy_Header.get_keywords Pure

val evaluated_theories = Thread_Data.var ()
val global_theories = Synchronized.var "global_theories" Symtab.empty

exception REPL_fail of string

fun is_theory_tok tok = Token.is_kind Token.Command tok andalso Token.content_of tok = "theory"

val loader_locker = Synchronized.var "REPL theory loader locker" ()

fun thy_loader import_dir thy_qualifier targets_str =
  let val cwd = Synchronized.change_result loader_locker (fn () =>
                    (OS.FileSys.getDir (), ()))
      val targets = map (Resources.import_name thy_qualifier (the_default Path.root import_dir))
                        targets_str
      val evaluated_theories = the_default Symtab.empty (Thread_Data.get evaluated_theories)
      val can_load = Execution.is_running Document_ID.none
      fun is_loaded import =
          Symtab.defined evaluated_theories import orelse
          is_some (Thy_Info.lookup_theory import) orelse
          Symtab.defined (Synchronized.value global_theories) import


      val _ = Synchronized.change loader_locker (fn () =>
        let val targets = filter_out (is_loaded o #theory_name) targets
            val _ = if not can_load andalso not (null targets)
                    then raise REPL_fail (
                              "Fail to load " ^ space_implode ", " (map #theory_name targets))
                    else ()
            val target_groups = partition_eq (op = o apply2 #master_dir) targets
            fun load_group works = (
                OS.FileSys.chDir (Path.implode (#master_dir (hd works)))
              ; if null targets
                then ()
                else (Thy_Info.use_theories (Options.default ()) thy_qualifier
                                            (map (rpair Position.none o #theory_name) works) ; ()))
         (* fun seg_load L =
              if null L
              then ()
              else let val (this, next) = chop 16 L
                    in Thy_Info.use_theories (Options.default ()) thy_qualifier
                                        (map (rpair Position.none) this)
                     ; seg_load next
                   end *)
         in \<^try>\<open> List.app load_group target_groups
            finally
              OS.FileSys.chDir cwd \<close>
            (* seg_load targets *)
        end)

      fun load' import =
        case Symtab.lookup evaluated_theories import
          of SOME thy => thy
           | NONE     => (
        case Thy_Info.lookup_theory import
          of SOME thy => thy
           | NONE     =>
        case Symtab.lookup (Synchronized.value global_theories) import
          of SOME thy => thy
           | NONE =>
         raise REPL_fail ("Bad theory import " ^ import)
        )
   in map (load' o #theory_name) targets
  end

fun add_evaluated_theories entry =
  let val store  = the_default Symtab.empty (Thread_Data.get evaluated_theories)
      val store' = Symtab.update entry store
   in Thread_Data.put evaluated_theories (SOME store')
  end

fun add_global_theories entry =
  Synchronized.change global_theories (Symtab.update entry)

fun init_thy ignore_imports (base_dir, {thy_qualifier, additional_libs, import_dir, attributes,...}) source =
  let val toks = Token.tokenize pure_keywords {strict = false} source
      val i = find_index is_theory_tok toks
   in if i = ~1
   then NONE
   else let
      val header_toks = List.drop (toks, i)
      val header = Thy_Header.read_tokens (Token.pos_of (hd header_toks)) header_toks
      val sname = #name header

      fun qualify_name {name,imports,keywords} =
            {name=apfst (Long_Name.qualify thy_qualifier) name, imports=imports, keywords=keywords}
      val header = qualify_name header

      (* init theory *)
      val imports = #imports header
                  @ map (rpair Position.none) additional_libs
      val evaluated_theories = the_default Symtab.empty (Thread_Data.get evaluated_theories)
      val _ = if Symtab.defined evaluated_theories (#1 sname)
              then raise REPL_fail ("Theory " ^ #1 sname ^ " has been defined.")
              else ()

      val parents =
            if ignore_imports then []
            else thy_loader import_dir thy_qualifier (map fst imports)
      val parents =
            if null parents then [Pure] else parents
   in Resources.begin_theory base_dir header parents
   |> Config.put_global Printer.show_markup false
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
   |> SOME
  end
  end

fun get_thy rm_thy cfg state source = (
      if can Toplevel.theory_of state <> Toplevel.is_toplevel state then ()
      else error "BUG: K/aPbPakSCOMOSqoevPh+g"
    ; case try Toplevel.theory_of state
          of SOME thy => thy
           | NONE =>
      case init_thy false cfg source
        of SOME thy => let
            val path = Path.append (Resources.master_directory thy)
                                   (Path.explode (Context.theory_name {long=false} thy ^ ".thy"))
             in if File.exists path andalso rm_thy then File.rm path else ()
              ; thy
            end
         | NONE => Pure)

(* fun split_commands src *)

fun parse_text' thy init text =
     Token.tokenize (Thy_Header.get_keywords thy) {strict = false} text
  |> Outer_Syntax.parse_spans
  |> map (` (Command_Span.content #> Outer_Syntax.parse_span thy init))

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

fun parse_text (base_dir, origin_base_dir, (cfg:cfg)) register_theory' state source =
  let val write_thy = register_theory' andalso
                      Path.expand origin_base_dir = Path.expand base_dir
      val thy = get_thy write_thy (base_dir,cfg) state source
   in if write_thy andalso not (pointer_eq (Pure, thy))
         andalso Path.expand (Resources.master_directory thy) = Path.expand base_dir
    then File.append (Path.append (Resources.master_directory thy)
                                  (Path.explode (Context.theory_name {long=false} thy ^ ".thy")))
                     (Symbol_Pos.content source)
    else ()
    ; parse_text' thy (K thy) source
   |> filter_out (Toplevel.is_ignored o fst)
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
fun catch_state' wid plugin_output err command s : command_output = {
        command_name = command,
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
        level   = Toplevel.level s,
        state   = trim_makrup (Toplevel.string_of_state s),
        plugin_output = plugin_output,
        errors  = trim_err err
    }

fun apply_single_cmd_timeout (Command_Span.Span (Command_Span.Command_Span (name, _), toks)) =
      let val bad = ["auto_sledgehammer", "sledgehammer"]
       in not (member (op =) bad name) andalso
          not (exists (fn tok => member (op =) bad (Token.content_of tok)) toks)
      end

fun RE (cfg:cfg) source : command_outputs =
  case Thread_Data.get state
    of NONE                  => {outputs=NONE, error=SOME "INTERNAL ERROR: state lost"}
     | SOME (s0,cnt,(trace, register_theory'),H) =>
  case Thread_Data.get Session_ID
    of NONE                => {outputs=NONE, error=SOME "INTERNAL ERROR: worker ID lost"}
     | SOME (wid, base_dir, origin_base_dir, plugins) =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1,
                  props= { label = the_default "" (#position_label cfg),
                           file = the_default "#REPL" (#file cfg),
                           id="" }
                }
      val srcs = Symbol_Pos.explode (source, pos)
              |> split_thy_headers

      fun catch_state plugin_output err tr s : command_output
        = catch_state' wid plugin_output err (Toplevel.name_of tr) s

      fun err_state err tr s : command_output = {
              command_name = Toplevel.name_of tr,
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
              level   = Toplevel.level s,
              state   = "",
              plugin_output = [],
              errors  = trim_err err
          }

      fun mk_command_outputs a b = {outputs = if trace then SOME (rev a) else NONE, error=b} : command_outputs

      fun loop ret _ [] [] s = (mk_command_outputs ret NONE, s)
        | loop ret errs [] (src::srcs) s =
            loop ret errs (parse_text (base_dir, origin_base_dir, cfg) register_theory' s src) srcs s
        | loop ret errs ((tr,current_cmd)::trs) srcs s =
            case (case #single_cmd_timeout cfg
                    of NONE => Toplevel.command_errors false tr s
                     | SOME time =>
                          if apply_single_cmd_timeout current_cmd
                          then Timeout.apply time (Toplevel.command_errors false tr) s
                               handle Timeout.TIMEOUT t =>
                                  ([((serial(), "Timeout after " ^ Time.toString t ^ "s"), NONE)], NONE)
                          else Toplevel.command_errors false tr s )
              of (err, NONE)    =>
                  let val Er = case trim_err err @ errs
                                 of [] => "Some error happens. Details may be given in the field `outputs.errors.` \
                                          \See the document for Python client's `boring_parse` method. "
                                  | Er => String.concatWith "\n\n" Er
                   in (mk_command_outputs (if trace then err_state err tr s::ret else [])
                                          (SOME Er), s0)
                  end
               | (err, SOME s'0) =>
                let val (plugin_output, s') = run_plugins cfg plugins (current_cmd, trs, s'0)
                    val _ = if Toplevel.is_end_theory s'
                            then if register_theory'
                              then let
                                val thys = the_default Symtab.empty (Thread_Data.get evaluated_theories)
                                val thy  = Toplevel.end_theory pos s'
                                val thys'= Symtab.update_new (Context.theory_name {long=true} thy, thy) thys
                                in Thread_Data.put evaluated_theories (SOME thys')
                                 ; (Thy_Info.register_thy thy
                                    handle err as Exn.ERROR msg => (
                                      if String.isPrefix "Cannot update finished theory" msg
                                      then ()
                                      else Exn.reraise err ))
                               end
                              else ()
                            else ()
                 in loop (if trace then (catch_state plugin_output err tr s')::ret else [])
                         (trim_err err @ errs)
                         trs srcs s'
                end

      val (ret, s') = loop [] [] [] srcs s0

   in Thread_Data.put state (SOME (s', cnt+1, (trace, register_theory'), H))
    ; ret
  end
  handle REPL_fail E => {outputs = NONE, error=SOME E}

val ID_counter = Counter.make ()

fun init_repler base_base thy =
  let val id = ID_counter ()
      val base_dir = Path.append base_base (Path.basic (string_of_int id))
      val _ = if File.is_dir base_dir
              then ()
              else ( if File.exists base_dir then File.rm base_dir else ();
                     OS.FileSys.mkDir (File.platform_path base_dir) )
   in Thread_Data.put Session_ID (SOME (id, base_dir, base_dir, []))
    ; Synchronized.change message_buffer (Inttab.update_new (id, []))
    ; Thread_Data.put state (SOME (Toplevel.make_state thy, 0, (true, true), []))
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
       val s' = Toplevel.command_exception false tr s0
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
     | SOME (_,base_dir,_,_) =>
  case Thread_Data.get state
    of NONE              => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s0,cnt,_,_) =>
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=""}}
      fun parse [] = []
        | parse (src::srcs) =
        let val thy = case init_thy true (base_dir, cfg) src
                        of SOME thy => thy
                         | NONE => the_default Pure (try Toplevel.theory_of s0)
            val kws = Thy_Header.get_keywords thy
            val ret = lex_split true true kws Token.is_command_modifier (Token.is_kind Token.Command) src

            val thys = the_default Symtab.empty (Thread_Data.get evaluated_theories)
            val thys'= Symtab.update_new (Context.theory_name {long=true} thy, thy) thys
            fun pos_of [] = Position.none
              | pos_of (h :: _) = snd h
         in map (fn syms => (pos_of syms, Symbol_Pos.implode syms)) ret
         :: Thread_Data.setmp evaluated_theories (SOME thys') parse srcs
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
     | SOME (_, _, _, plugins) =>
        AList.lookup (op =) plugins name

fun register_plugin plugin =
  case Thread_Data.get Session_ID
    of NONE               => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (wid, base, origin_base, plugins) =>
        Thread_Data.put Session_ID (SOME (wid, base, origin_base, add_plugin plugin plugins))

fun delete_plugin name =
  case Thread_Data.get Session_ID
    of NONE               => raise REPL_fail "INTERNAL ERROR: worker ID lost"
     | SOME (wid, base, origin_base, plugins) =>
        Thread_Data.put Session_ID (SOME (wid, base, origin_base, remove_plugin name plugins))

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
     | SOME (wid, _, _, plugins) =>
  case Thread_Data.get state
    of NONE             => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,cnt,t,H) =>
  case AList.lookup (op =) H name
    of NONE => raise REPL_fail ("Historical state " ^ name ^ " is not found.")
     | SOME s' => let
       val (plugin_output, s'') =
            run_plugins cfg plugins (Command_Span.Span
                                        (Command_Span.Command_Span ("<rollback>", Position.none), []),
                                     [],
                                     s')
    in Thread_Data.put state (SOME (s'', cnt, t, H))
     ; catch_state' wid plugin_output [] "" s'
   end

fun rollback_state_global cfg name store =
  case Thread_Data.get Session_ID
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, _, _, plugins) =>
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
                                        (Command_Span.Command_Span ("<rollback>", Position.none), []),
                                     [],
                                     s')
    in Thread_Data.put state (SOME (s'', cnt, t, H))
     ; catch_state' wid plugin_output [] "" s'
   end

fun list_states () =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,_,_,H) => H

fun list_states' cfg () =
  case Thread_Data.get Session_ID
    of NONE                => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, _, _, plugins) =>
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,_,_,H) => map (apsnd (fn s' =>
          catch_state' wid (#1 (
            run_plugins cfg plugins (Command_Span.Span
                                        (Command_Span.Command_Span ("<list>", Position.none), []),
                                     [],
                                     s')
          )) [] "" s'
       )) H

(** Parser **)

fun parse_term term =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) => (
  case try Toplevel.context_of s
    of SOME ctxt => (ctxt, Syntax.read_term ctxt term)
     | NONE     => raise REPL_fail "Not in a theory context.\n\
            \You must evaluate at least a theory head (e.g., 'theory THY imports Main begin') to \
            \indicate the theory under which the term will be parsed." )

fun retrieve_fact name =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) => (
  case try Toplevel.context_of s
    of SOME ctxt =>
      let val keywords = Thy_Header.get_keywords (Proof_Context.theory_of ctxt)
          val thms = Parse.read_embedded ctxt keywords Parse.thms1 (Input.string name)
                  |> Attrib.eval_thms ctxt
       in (ctxt, thms)
      end
     | NONE     => raise REPL_fail "Not in a theory context.\n\
            \You must evaluate at least a theory head (e.g., 'theory THY imports Main begin') to \
            \indicate the theory under which the term will be parsed." )

(** Sledgehammer **)

fun sledgehammer timeout' =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) => (
  case try Toplevel.proof_of s
    of SOME stat =>
       let val timeout = Time.fromSeconds timeout'
        in (if timeout' <= 0 then I else Timeout.apply_physical timeout) (fn () => let
           val ctxt = Proof.context_of stat
                   |> (if timeout' <= 0 then I 
                       else Config.map Phi_Sledgehammer_Solver.sledgehammer_params
                                 (fn s => "timeout = " ^ string_of_int timeout' ^ ", " ^ s))
           val goal = Proof.goal stat |> #goal
           val (prf, _) = Phi_Sledgehammer_Solver.auto true Sledgehammer_Fact.no_fact_override NONE ctxt goal
        in prf
       end) ()
       end
     | NONE      => raise REPL_fail "Not in a proof context." )

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

fun get_context () =
  let val s = get_toplevel_state ()
   in case (try Toplevel.context_of s, try Toplevel.proof_of s)
    of (SOME ctxt, prfstate) =>
      let
        val facts = Proof_Context.facts_of ctxt
        val props = map #1 (Facts.props facts)

        val facts' = if can Local_Theory.assert ctxt
             then Proof_Context.facts_of (Local_Theory.target_of ctxt)
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
  end

fun get_ctxt () =
  case Thread_Data.get state
    of NONE           => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (s,_,_,_) => (
  case try Toplevel.context_of s
    of SOME ctxt => ctxt
     | NONE => raise REPL_fail "Not in a proof context." )

(** set base_dir **)

fun get_base_dir () =
  case Thread_Data.get Session_ID
    of NONE              => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (_,base,_,_) => base

fun set_base_dir base' =
  case Thread_Data.get Session_ID
    of NONE              => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, _, origin_base, H) =>
       Thread_Data.put Session_ID (SOME (wid, base', origin_base, H))

fun reset_base_dir () =
  case Thread_Data.get Session_ID
    of NONE              => raise REPL_fail  "INTERNAL ERROR: state lost"
     | SOME (wid, _, origin_base, H) =>
       Thread_Data.put Session_ID (SOME (wid, origin_base, origin_base, H))

(** Auxiliary **)

val dot_path = Path.explode "."

fun path_of_the_theory (cfg:cfg) name =
  let val dir = the_default Path.root (#import_dir cfg)
      val {master_dir, theory_name, ...} = Resources.import_name (#thy_qualifier cfg) dir name
      val evaluated_theories = the_default Symtab.empty (Thread_Data.get evaluated_theories)
      fun path_of thy =
        Path.append (Resources.master_directory thy)
                    (Path.basic (Context.theory_name {long=false} thy ^ ".thy"))
   in case Symtab.lookup evaluated_theories theory_name
        of SOME thy => path_of thy
         | NONE     => (
      case Thy_Info.lookup_theory name
        of SOME thy => path_of thy
         | NONE     =>
      case Symtab.lookup (Synchronized.value global_theories) name
        of SOME thy => path_of thy
         | NONE =>
      if master_dir = dot_path
      then raise REPL_fail ("Fail to infer the path of the theory " ^ name)
      else Path.append master_dir (Path.basic (Long_Name.base_name theory_name ^ ".thy")) 
      )
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
      val header = Thy_Header.read_tokens pos toks
      fun qualify_name {name,imports,keywords} =
            {name=apfst (Long_Name.qualify (#thy_qualifier cfg)) name, imports=imports, keywords=keywords}
      val header = qualify_name header
   in header
  end

end

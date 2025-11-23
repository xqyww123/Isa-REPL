signature REPL_AUX = sig

(*Given a path to a file, `parse_session_name` tries to find the name of the session to which
  the file belongs*)
val parse_session_name : Path.T -> string option
val collect_thy_dirs : Path.T list -> Path.T list
val session_theory_infos :
      ( {deps: string list, theories: string list} Symtab.table
      * {imports: string list, keywords: Thy_Header.keywords, path: Path.T} Symtab.table
      ) lazy

val parse_thy_header : Path.T -> Thy_Header.header list

val column_of_pos : string -> (Position.T -> int * int) * (Position.T -> Position.T)

end

structure REPL_Aux : REPL_AUX = struct

local

val groups =
  Scan.optional (Parse.$$$ "(" |-- Parse.!!! (Scan.repeat1 Parse.name --| Parse.$$$ ")")) [];

val description =
  Scan.optional (Parse.$$$ "description" |-- Parse.!!! (Parse.input Parse.embedded)) Input.empty;

val theory_entry = Parse.input Parse.theory_name --| Parse.opt_keyword "global";

val theories =
  Parse.$$$ "theories" |-- Parse.!!! (Scan.optional Parse.options [] -- Scan.repeat1 theory_entry);

val document_theories =
  Parse.$$$ "document_theories" |-- Scan.repeat1 (Parse.input Parse.theory_name);

val document_files =
  Parse.$$$ "document_files" |--
    Parse.!!! (Parse.in_path_parens "document" -- Scan.repeat1 Parse.path_input);

val prune =
  Scan.optional (Parse.$$$ "[" |-- Parse.!!! (Parse.nat --| Parse.$$$ "]")) 0;

val export_files =
  Parse.$$$ "export_files" |--
    Parse.!!! (Parse.in_path_parens "export" -- prune -- Scan.repeat1 Parse.embedded);

val export_classpath =
  Parse.$$$ "export_classpath" |-- Scan.repeat Parse.embedded;

fun path_source source path =
  Input.source (Input.is_delimited source) (Path.implode path) (Input.range_of source);

in

val chapter_definition_parser =
  Parse.chapter_name -- groups -- description >> K ();

val session_parser =
  Parse.session_name -- groups -- Parse.in_path "." --
  (Parse.$$$ "=" |--
    Parse.!!! (Scan.option (Parse.session_name --| Parse.!!! (Parse.$$$ "+")) -- description --
      Scan.optional (Parse.$$$ "options" |-- Parse.!!! Parse.options) [] --
      Scan.optional (Parse.$$$ "sessions" |--
        Parse.!!! (Scan.repeat1 Parse.session_name)) [] --
      Scan.optional (Parse.$$$ "directories" |-- Parse.!!! (Scan.repeat1 Parse.path_input)) [] --
      Scan.repeat theories --
      Scan.optional document_theories [] --
      Scan.repeat document_files --
      Scan.repeat export_files --
      Scan.optional export_classpath []))
  >> (fn (((((session, _), _), dir), ((((((((((parent, _), _), sessions), dirs), theories), _), _), _), _)))) =>
    let val dir = Path.explode (Input.string_of dir)
        val dirs= map (Path.explode o Input.string_of) dirs
        fun parse_thy path = Path.expand (dir + Path.explode (Input.string_of path))
        val deps = map fst (the_list parent @ sessions)
     in (session,
         map (map parse_thy o snd) theories |> flat,
         deps,
         dir,
         dirs)
    end )

val ROOT = Path.explode("ROOT")

val keywords = Thy_Header.get_keywords \<^theory>\<open>Pure\<close>
            |> Keyword.add_keywords (
                map (fn name => ((name, Position.none), Keyword.quasi_command_spec))
                ["description", "directories", "options", "sessions", "theories",
                 "document_theories", "document_files", "export_files", "global" ]
              @ map (fn name => ((name, Position.none), Keyword.command_spec (Keyword.thy_decl, [])))
                ["chapter_definition", "session"])

fun tokenize keywords = Token.tokenize keywords {strict = true} #> filter Token.is_proper;

fun find_session input =
  let val toks = tokenize keywords (Input.source_explode input);
      fun auto NONE ret [] = ret
        | auto (SOME buf) ret [] = rev (Token.eof :: buf) :: ret
        | auto NONE ret (tok::toks) =
            if Token.is_kind Token.Command tok andalso
               Token.content_of tok = "session"
            then auto (SOME []) ret toks
            else auto NONE ret toks
        | auto (SOME buf) ret (tok::toks) =
            if Token.is_kind Token.Command tok
            then auto NONE (rev (Token.eof :: buf) :: ret) (tok::toks)
            else auto (SOME (tok::buf)) ret toks
   in auto NONE [] toks
   |> map session_parser
  end

end

fun parse_session_name target_path =
  let val target_path = Path.expand target_path
      val (target, _) = Path.split_ext target_path
      val short_name = Path.file_name target
      fun find base =
        case try ( File.read
                #> Input.string
                #> find_session            
                #> map fst
                 ) (base + ROOT)
          of SOME sessions => sessions
              |> get_first (fn (session, thys, _, _, _) =>
                    if exists (fn thy => base + thy = target) thys
                    then SOME session
                    else NONE)
              |> (fn NONE => 
                  let fun best_dir pathss current =
                        let val pathss = map (apfst (map Path.expand)) pathss
                            fun chk current =
                              case get_first (fn (xs, session) =>
                                    get_first (fn x =>
                                      if x = current andalso
                                        (case Resources.find_theory_file (Long_Name.qualify session short_name)
                                           of SOME target_path' => target_path = target_path'
                                            | NONE => false)
                                      then SOME session
                                      else NONE
                                      ) xs
                                   ) pathss
                                of SOME ret => SOME ret
                                 | NONE => (case try Path.dir current
                                of SOME current' => chk current'
                                 | NONE => NONE)
                         in chk (Path.expand current)
                        end
                      val paths = map (fn (session, _, _, major_dir,dirs) =>
                                        (    (base + major_dir)
                                          :: map (fn dir => base + major_dir + dir) dirs,
                                         session)) sessions
                   in case best_dir paths target_path
                        of NONE => (case try Path.dir base
                                      of SOME base' => find base'
                                       | NONE => NONE )
                         | some => some
(* try Path.dir dir
                          |> Option.mapPartial (fn dir' =>
                                case find false dir'
                                  of NONE => if top andalso (case sessions of [_] => true | _ => false)
                                             then SOME (#1 (hd sessions))
                                             else NONE
                                   | some => some) *)
                  end
                   | some => some)
           | _ => try Path.dir base
               |> Option.mapPartial find
   in try Path.dir target_path
   |> Option.mapPartial find
  end

fun is_comment s =
  let val i = Unsynchronized.ref 0
      val sz = size s
      val ret = Unsynchronized.ref false
   in while !i < sz do (
      ( case String.sub (s, !i)
          of #" " => ()
           | #"#" => (ret := true; i := sz)
           | _    => i := sz )
      ; i := !i + 1
      )
    ; !ret
  end

fun collect_thy_dirs0 ret [] = ret
  | collect_thy_dirs0 ret paths =
      let val new_dirs = maps (fn path =>
                  let val roots = Path.append path (Path.basic "ROOTS")
                   in if File.is_file roots
                    then File.read_lines roots
                      |> filter_out is_comment
                      |> map (fn name => Path.expand (Path.append path (Path.explode name)))
                    else []
                  end
                ) paths
              |> distinct (op =)
              |> subtract (op =) ret
       in collect_thy_dirs0 (new_dirs @ ret) new_dirs
      end
fun collect_thy_dirs paths = collect_thy_dirs0 paths paths

fun parse_thy_header path =
  let val pos = Position.make {
                  line=1, offset=1, end_offset=1,
                  props= { label = "", file = Path.implode path, id="" }
                }
   in Symbol_Pos.explode (File.read path, pos)
   |> REPL.split_thy_headers
   |> map (Token.tokenize REPL.pure_keywords {strict=false})
   |> map_filter (try (Thy_Header.read_tokens Position.none))
  end

fun has_slash s =
  let val sz = size s
      val i = Unsynchronized.ref 0
      val ret = Unsynchronized.ref false
   in while !i < sz do (
        if String.sub (s, !i) = #"/"
        then (ret := true; i := sz)
        else i := !i + 1 )
    ; !ret
  end

fun qualify_name sname name =
       if Long_Name.is_qualified name
       then name
       else Long_Name.qualify sname name

fun parse_import dir sname name =
      if is_some (Resources.global_theory name)
      then SOME name
      else if has_slash name
      then let
           val path' = Path.explode name
        in case parse_session_name (dir + Path.ext "thy" path')
             of NONE => (warning (Path.implode (dir + Path.ext "thy" path')); NONE)
              | SOME session => SOME (qualify_name session (Path.file_name path'))
       end
      else SOME (qualify_name sname name)

fun collect_theory sname0 thy_name (tinfo, thys) =
      (case Resources.find_theory_file thy_name
         of NONE => error "BUG Resources.find_theory_file"
          | SOME path =>
              let val sname' = Resources.theory_qualifier thy_name
                  val {imports,keywords,...} = Resources.check_thy (Path.dir path) thy_name
                  val dir = Path.dir path
                  val imports = map_filter (parse_import dir sname' o fst) imports
                  val recursive_targets = imports
                          |> filter (fn name => not (Symtab.defined tinfo name) )
                  val info = {imports=imports, keywords=keywords, path=path}
               in (Symtab.update (thy_name, info) tinfo,
                   if sname' = sname0 then insert (op =) thy_name thys
                                      else thys)
               |> fold (collect_theory sname0) recursive_targets
              end )

fun mk_session_info paths (*Isabelle components*) =
  let val dirs = collect_thy_dirs paths
   in fold (fn path0 =>
         let val path = Path.append path0 (Path.basic "ROOT")
          in if File.is_file path
             then let
             val sessions = File.read path
                         |> Input.string
                         |> find_session
                         |> map fst
          in fold (fn (sname, raw_thys, deps, _, _) => fn (sinfo, tinfo) =>
            let 
                val thy_names = map_filter (parse_import path0 sname o Path.implode) raw_thys
                val (tinfo', thys') = fold (collect_theory sname) thy_names (tinfo, [])
             in (Symtab.update_new (sname, {deps=deps, theories=thys'}) sinfo,
                 tinfo')
            end
           ) sessions
         end else I
         end
      ) dirs (Symtab.empty, Symtab.empty)
  end

val session_theory_infos = Lazy.lazy (fn () => (
    let val etc_components = Path.explode "etc/components"
        val isabelle_home = getenv "ISABELLE_HOME"
        val components = [getenv "ISABELLE_HOME_USER", isabelle_home]
                          |> map (fn s => Path.expand (Path.append (Path.explode s) etc_components))
                          |> maps (fn path =>
                              if File.is_file path
                              then File.read_lines path
                                |> filter_out is_comment
                                |> map (fn s => if String.isPrefix "/" s
                                                then s
                                                else isabelle_home ^ "/" ^ s )
                              else [] )
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/HOL")
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/Pure")
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/Tool")
                          |> map Path.explode
     in mk_session_info components
    end
  ))


fun column_of_pos src =
  let val ofs  = Unsynchronized.ref 1
      val line = Unsynchronized.ref 1
      val colm = Unsynchronized.ref 1
      val src = Symbol_Pos.explode (src, Position.none)
             |> Vector.fromList
             |> Vector.map fst
      fun calc offset = (
          if offset < !ofs then (ofs := 1; line := 1; colm := 0) else ()
        ; while !ofs < offset do
            let val s = Vector.sub (src, !ofs)
             in if s = "\n"
              then (line := !line + 1; ofs := !ofs + 1; colm := 0)
              else (ofs := !ofs + 1; colm := !colm + size s)
            end
        )
      fun of_pos pos =
        let val _ = calc (the (Position.offset_of pos))
            val c0 = !colm
         in case Position.end_offset_of pos
              of SOME x1 => (
                    calc x1
                  ; (c0, !colm) )
               | NONE => (c0, ~1)
        end
      fun translate_pos pos =
        let val (c0, c1) = of_pos pos
         in Position.make0 (the (Position.line_of pos)) c0 c1
                           (the_default "" (Position.label_of pos))
                           (the_default "" (Position.file_of pos))
                           (the_default "" (Position.id_of pos))
        end
   in (of_pos, translate_pos)
  end 

end

val REPL_ML_sender_DO_NOT_OVERRIDE_ : REPL.collector option Unsynchronized.ref
      = Unsynchronized.ref NONE
val REPL_ML_sender2_DO_NOT_OVERRIDE_ : (unit -> unit) option Unsynchronized.ref
      = Unsynchronized.ref NONE
val REPL_ML_sender_DO_NOT_OVERRIDE_locker_
      = Synchronized.var "REPL_ML_sender_DO_NOT_OVERRIDE_locker_" ()

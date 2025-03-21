signature REPL_AUX = sig

(*Given a path to a file, `parse_session_name` tries to find the name of the session to which
  the file belongs*)
val parse_session_name : Path.T -> string option
val collect_thy_dirs : Path.T list -> Path.T list
val session_theory_infos :
      ( {deps: string list, theories: string list} Symtab.table
      * (Thy_Header.header * Path.T) Symtab.table
      ) lazy

val parse_thy_header : Path.T -> Thy_Header.header list

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
  >> (fn (((((session, _), _), dir), ((((((((((parent, _), _), sessions), _), theories), _), _), _), _)))) =>
    let val dir = Path.explode (Input.string_of dir)
        fun parse_thy path = Path.expand (dir + Path.explode (Input.string_of path))
        val deps = map fst (the_list parent @ sessions)
     in (session,
         map (map parse_thy o snd) theories |> flat,
         deps)
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

fun parse_session_name path =
  let val path = Path.expand path
      val (target, _) = Path.split_ext path
      fun find top dir =
        case try ( File.read
                #> Input.string
                #> find_session            
                #> map fst
                 ) (dir + ROOT)
          of SOME sessions => sessions
              |> get_first (fn (session, thys, _) =>
                    if exists (fn thy => dir + thy = target) thys
                    then SOME session
                    else NONE)
              |> (fn NONE => try Path.dir dir
                          |> Option.mapPartial (fn dir' =>
                                case find false dir'
                                  of NONE => if top andalso (case sessions of [_] => true | _ => false)
                                             then SOME (#1 (hd sessions))
                                             else NONE
                                   | some => some)
                   | some => some)
           | _ => try Path.dir dir
               |> Option.mapPartial (find top)
   in try Path.dir target
   |> Option.mapPartial (find true)
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

fun collect_thy_dirs0 [] = []
  | collect_thy_dirs0 paths =
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
              |> subtract (op =) paths
       in new_dirs @ collect_thy_dirs0 new_dirs
      end
fun collect_thy_dirs paths = paths @ collect_thy_dirs0 paths

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
          in fold (fn (sname, thys, deps) => fn (sinfo, tinfo) =>
            let val headerss = map_filter (fn thy =>
                        try (` parse_thy_header) (path0 + Path.ext "thy" thy)) thys
                val (tinfo', thys') = fold (fn (headers,path) =>
                      fold (fn header => fn (tinfo, thys) =>
                        let fun qualify_name name =
                                   if Long_Name.is_qualified name
                                   then name
                                   else Long_Name.qualify sname name
                            fun parse_import name =
                                  if has_slash name
                                  then parse_thy_header (path0 + Path.ext "thy" (Path.explode name))
                                    |> hd
                                    |> #name
                                    |> fst
                                    |> qualify_name
                                  else qualify_name name
                            val header = { name = #name header,
                                           imports = map_filter (try (apfst parse_import)) (#imports header),
                                           keywords = #keywords header }
                            val name = qualify_name (fst (#name header))
                         in (Symtab.update (name, (header, path)) tinfo,
                             insert (op =) name thys)
                        end ) headers
                    ) headerss (tinfo, [])
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
        val components = [getenv "ISABELLE_HOME_USER", getenv "ISABELLE_HOME"]
                          |> map (fn s => Path.expand (Path.append (Path.explode s) etc_components))
                          |> maps (fn path =>
                              if File.is_file path
                              then File.read_lines path
                                |> filter_out is_comment
                              else [] )
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/HOL")
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/Pure")
                          |> insert (op =) (getenv "ISABELLE_HOME" ^ "/src/Tool")
                          |> map Path.explode
     in mk_session_info components
    end
  ))


end
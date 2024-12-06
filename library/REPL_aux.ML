signature REPL_AUX = sig

val parse_session_name : Path.T -> string option

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
  >> (fn (((((session, _), _), dir), ((((((_, theories), _), _), _), _)))) =>
    let val dir = Path.explode (Input.string_of dir)
        fun parse_thy path = Path.expand (dir + Path.explode (Input.string_of path))
     in (session, map (map parse_thy o snd) theories |> flat)
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
   |> map (session_parser #> fst)
  end

end

fun parse_session_name path =
  let val path = Path.expand path
      val (target, _) = Path.split_ext path
      fun find top dir =
        case try ( File.read
                #> Input.string
                #> find_session
                 ) (dir + ROOT)
          of SOME sessions => sessions
              |> get_first (fn (session, thys) =>
                    if exists (fn thy => dir + thy = target) thys
                    then SOME session
                    else NONE)
              |> (fn NONE => try Path.dir dir
                          |> Option.mapPartial (fn dir' =>
                                case find false dir'
                                  of NONE => if top andalso (case sessions of [_] => true | _ => false)
                                             then SOME (fst (hd sessions))
                                             else NONE
                                   | some => some)
                   | some => some)
           | _ => try Path.dir dir
               |> Option.mapPartial (find top)
   in try Path.dir target
   |> Option.mapPartial (find true)
  end


end
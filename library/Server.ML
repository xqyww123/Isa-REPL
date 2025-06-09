signature REPL_SEVER = sig

type address = string (*IP address:port*)

val startup : Path.T -> theory option -> address -> Isabelle_Thread.T
val kill_server : address -> unit

type App = (BinIO.StreamIO.instream Unsynchronized.ref * BinIO.StreamIO.outstream) -> unit
val register_app : string -> App -> unit
val app_of : string -> App option

val socket_in_of  : unit -> BinIO.StreamIO.instream Unsynchronized.ref
val socket_out_of : unit -> BinIO.StreamIO.outstream

val output_err : BinIO.StreamIO.outstream -> string -> unit
val output     : BinIO.StreamIO.outstream -> 'a MessagePackBinIO.Pack.packer -> 'a -> unit

end

val REPL_ML_sender_DO_NOT_OVERRIDE_ : REPL.collector option Unsynchronized.ref
      = Unsynchronized.ref NONE
val REPL_ML_sender2_DO_NOT_OVERRIDE_ : (unit -> unit) option Unsynchronized.ref
      = Unsynchronized.ref NONE
val REPL_ML_sender_DO_NOT_OVERRIDE_locker_
      = Synchronized.var "REPL_ML_sender_DO_NOT_OVERRIDE_locker_" ()

structure REPL_Server : REPL_SEVER = struct

(* App *)

type App = (BinIO.StreamIO.instream Unsynchronized.ref * BinIO.StreamIO.outstream) -> unit
val apps = Thread_Data.var () : App Symtab.table Unsynchronized.ref Thread_Data.var

fun app_of name =
  case Thread_Data.get apps
    of SOME apps => Symtab.lookup (!apps) name
     | NONE => NONE

fun register_app name app =
  let val apps = case Thread_Data.get apps
                   of SOME rf => rf
                    | NONE => let val rf = Unsynchronized.ref Symtab.empty
                               in Thread_Data.put apps (SOME rf)
                                ; rf
                              end
   in apps := Symtab.update (name, app) (!apps)
  end

val sockets = Thread_Data.var ()
fun socket_in_of  () = the (Thread_Data.get sockets) |> fst
fun socket_out_of () = the (Thread_Data.get sockets) |> snd

(* Server *)

type address = string (*IP address:port*)

fun close_permissive socket =
  Socket.close socket handle OS.SysErr _ => ();

fun make_streams socket =
  let
    val (host, port) = INetSock.fromAddr (Socket.Ctl.getSockName socket);
    val name = NetHostDB.toString host ^ ":" ^ string_of_int port;

    val rd =
      BinPrimIO.RD {
        name = name,
        chunkSize = 4096,
        readVec = SOME (fn n => Socket.recvVec (socket, n)),
        readArr = SOME (fn buffer => Socket.recvArr (socket, buffer)),
        readVecNB = NONE,
        readArrNB = NONE,
        block = NONE,
        canInput = NONE,
        avail = fn () => NONE,
        getPos = NONE,
        setPos = NONE,
        endPos = NONE,
        verifyPos = NONE,
        close = fn () => close_permissive socket,
        ioDesc = NONE
      };

    val wr =
      BinPrimIO.WR {
        name = name,
        chunkSize = 4096,
        writeVec = SOME (fn buffer => Socket.sendVec (socket, buffer)),
        writeArr = SOME (fn buffer => Socket.sendArr (socket, buffer)),
        writeVecNB = NONE,
        writeArrNB = NONE,
        block = NONE,
        canOutput = NONE,
        getPos = NONE,
        setPos = NONE,
        endPos = NONE,
        verifyPos = NONE,
        close = fn () => close_permissive socket,
        ioDesc = NONE
      };

    val in_stream =
      BinIO.StreamIO.mkInstream (rd, Word8Vector.fromList []);

    val out_stream =
      BinIO.StreamIO.mkOutstream (wr, IO.BLOCK_BUF);

  in (in_stream, out_stream) end

fun compile_plugin ctxt source =
  let val pos = Position.make {
              line=1, offset=1, end_offset=1, props={label="", file="#REPL", id=""}}
      val ret : REPL.collector option Unsynchronized.ref = Unsynchronized.ref NONE
   in Synchronized.change REPL_ML_sender_DO_NOT_OVERRIDE_locker_ (fn () => (

        ML_Context.expression pos
            (ML_Lex.read "REPL_ML_sender_DO_NOT_OVERRIDE_ := SOME (" @
             ML_Lex.read source @
             ML_Lex.read ")")
            ctxt ;
        ret := ! REPL_ML_sender_DO_NOT_OVERRIDE_ ;
        REPL_ML_sender_DO_NOT_OVERRIDE_ := NONE 
      ))
    ; the (! ret)
  end


fun run_ML ctxt source =
  let val pos = Position.make {
              line=1, offset=1, end_offset=1, props={label="", file="#REPL-ML", id=""}}
      val ret = Unsynchronized.ref NONE
   in Synchronized.change REPL_ML_sender_DO_NOT_OVERRIDE_locker_ (fn () => (
        ML_Context.expression pos (
            ML_Lex.read "REPL_ML_sender2_DO_NOT_OVERRIDE_ := SOME (fn () => (" @
            ML_Lex.read source @
            ML_Lex.read "))"
          ) ctxt ;
        ret := ! REPL_ML_sender2_DO_NOT_OVERRIDE_ ;
        REPL_ML_sender2_DO_NOT_OVERRIDE_ := NONE
      ))
    ; the (!ret) ()
  end


val servers = Synchronized.var "REPL Servers" (Symtab.empty : Isabelle_Thread.T Symtab.table)

local open MessagePackBinIO.Unpack MessagePackBinIO.Pack in
fun output_err cout s =
  doPack (packPair (packUnit, packString))
                             ((), REPL.trim_makrup s) cout
fun output cout pack x = (
    doPack (packPair (pack, packUnit)) (x, ()) cout
  )
end

fun pos_packer pos =
  let open MessagePackBinIO.Unpack MessagePackBinIO.Pack
      val {line, offset, end_offset, props} = Position.dest pos
      val {label, file, id} = props
   in packTuple4 (packInt, packInt, packInt, packTuple3 (packString, packString, packString))
      (line, offset, end_offset, (label, file, id))
  end


fun column_to_offset src (line, column) =
  let val ofs = Unsynchronized.ref 0
      val ln = Unsynchronized.ref 1
   in while !ln < line do
        case String.sub(src, !ofs)
          of #"\n" => (  ln := !ln + 1
                      ; ofs := !ofs + 1 )
           | _ => ofs := !ofs + 1
    ; !ofs + Int.max (column - 1, 0)
  end

structure Postab = Table(type key = string * int val ord = prod_ord fast_string_ord int_ord);

val supervision_threads = Synchronized.var "supervision_threads" NONE
fun run_resource_supervison base_dir =
  let val sleep_time = Time.fromSeconds 10
      val threshold = ceil (real (Value.parse_int (getenv "ML_MAX_HEAP") * 1000000000) * 0.95)
      fun run () =
        File_Stream.open_output (fn stream =>
         let val last_time = Unsynchronized.ref 0.0
             val last_time_GC = Unsynchronized.ref 0.0
             val bad_count = Unsynchronized.ref 0
          in while true do let
                val stat = ML_Statistics.get()
                val size_heap = Value.parse_int (the (AList.lookup (op =) stat "size_heap"))
                val now_time = Value.parse_real (the (AList.lookup (op =) stat "time_elapsed"))
                val now_time_GC = Value.parse_real (the (AList.lookup (op =) stat "time_elapsed_GC"))
                val bad = size_heap > threshold andalso
                            (now_time_GC - !last_time_GC) / (now_time - !last_time) >= 0.7
             in last_time_GC := now_time_GC
              ; last_time := now_time
              ; if bad then bad_count := 1 + !bad_count
                       else bad_count := 0
              ; if !bad_count >= 3 then
                    OS.Process.terminate OS.Process.failure
                else ()
              ; File_Stream.outputs stream [Time.now () |> Time.toString, " : "]
              ; List.app (fn (k,v) =>
                  File_Stream.outputs stream [k, " = ", v, "  "] ) stat
              ; File_Stream.outputs stream ["\n"]
              ; BinIO.flushOut stream
              ; OS.Process.sleep sleep_time
            end
          ; ()
        end) (Path.append base_dir (Path.basic "ML_res_log"))
   in Synchronized.change supervision_threads (
        fn NONE => SOME (
                   Isabelle_Thread.fork ( Isabelle_Thread.params "ML_resource_supervison"
                                       |> Isabelle_Thread.stack_limit (1024 * 256)
                                       |> Isabelle_Thread.interrupts )
                                        run )
         | some => some)
  end


fun startup base_dir_of_theories thy0 addr0 =
  let val _ = if File.is_dir base_dir_of_theories
              then warning ("The base_dir_of_theories already exists. The shell may overwrite files.")
              else if File.exists base_dir_of_theories
              then error ("The base_dir_of_theories must be a directory : " ^ File.standard_path base_dir_of_theories)
              else OS.FileSys.mkDir (File.standard_path base_dir_of_theories)

      val default_session = getenv "REPL_DEFAULT_SESSION"

      val socket: Socket.passive INetSock.stream_sock = INetSock.TCP.socket ()
      val _ = Socket.Ctl.setREUSEADDR (socket, true)

      fun parse_addr socket_name =
         let fun err () = error ("Bad socket name: " ^ quote socket_name);
             val (host, port) =
                  (case space_explode ":" socket_name of [h, p] =>
                           (case NetHostDB.getByName h of SOME host => host | NONE => err (),
                            case Int.fromString p of SOME port => port | NONE => err ())
                     | _ => err ());
          in INetSock.toAddr (NetHostDB.addr host, port)
         end
      val addr = parse_addr addr0
      val _ = Socket.bind (socket, addr)
      val _ = Socket.listen (socket, 16)
      val msg = "Hi, this is Isabelle REPL Server.\n\
        \I'm now listening on " ^ addr0 ^ ". I will never terminate untill you kill me!"


      val evaluation_cache = Synchronized.var "evaluation_cache" Symtab.empty
      val evaluation_cache_store = Synchronized.var "evaluation_cache_store" Symtab.empty
      val evaluation_cache_counter = Counter.make ()

      val clients = Synchronized.var "REPL clients" (Inttab.empty : Isabelle_Thread.T Inttab.table)

      exception CONTINUE
   in writeln msg
    ; Output.physical_stdout msg
    ; Output.physical_stderr msg
    ; run_resource_supervison base_dir_of_theories
    ; Isabelle_Thread.fork (  Isabelle_Thread.params ("REPL server " ^ addr0)
                           |> Isabelle_Thread.interrupts )  (fn () => (
      Synchronized.change servers (Symtab.update_new (addr0, Isabelle_Thread.self ()))
    ; \<^try>\<open> while true do (
      let val (conn,sender) = Socket.accept socket
          val (cin, cout) = make_streams conn

          val (version, cin) = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
          val _ = if version = "0.11.0" then ()
                  else if version = "heartbeat"
                  then \<^try>\<open> (
                       output cout MessagePackBinIO.Pack.packUnit ()
                     ; BinIO.StreamIO.flushOut cout )
                    finally (
                       BinIO.StreamIO.closeOut cout
                     ; BinIO.StreamIO.closeIn  cin
                     ; raise CONTINUE ) \<close>
                  else if String.isPrefix "kill " version
                  then \<^try>\<open>
                   let val target = String.substring (version, 5, size version - 5)
                                 |> try Value.parse_nat
                                 |> the_default ~1
                       val dict = Synchronized.value clients
                       val found =
                            case Inttab.lookup dict target
                              of SOME T => (
                                   Isabelle_Thread.interrupt_thread T
                                 ; true )
                               | NONE   => false
                    in output cout MessagePackBinIO.Pack.packBool found
                     ; BinIO.StreamIO.flushOut cout
                   end
                    finally (
                       BinIO.StreamIO.closeOut cout
                     ; BinIO.StreamIO.closeIn  cin
                     ; raise CONTINUE )\<close>
                  else (
                    output_err cout "The server is connected with a wrong version of the client.\n\
                             \Please run `pip install \"IsaREPL==0.10.0\" --force-reinstall` to update your client."
                  ; BinIO.StreamIO.flushOut cout
                  ; BinIO.StreamIO.closeOut cout
                  ; BinIO.StreamIO.closeIn  cin
                  ; raise CONTINUE)

          val (thy_qualifier, cin) = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
          val cin = Unsynchronized.ref cin
          fun read unpacker = let open MessagePackBinIO.Unpack
                                  val (ret, cin') = doUnpack unpacker (!cin)
                                  val _ = cin := cin'
                               in ret
                              end

          val thy_qualifier = if thy_qualifier = ""
                              then if default_session = "Main"
                                   then "HOL"
                                   else default_session
                              else thy_qualifier
          val cfg = Unsynchronized.ref { thy_qualifier = thy_qualifier,
                                         file = NONE,
                                         position_label = NONE,
                                         additional_libs = [],
                                         import_dir = NONE,
                                         single_cmd_timeout = NONE,
                                         attributes = [] }

          fun iteration () =
            let open MessagePackBinIO.Unpack
                open MessagePackBinIO.Pack
                val source = read unpackString
             in \<^try>\<open> (
              if String.isPrefix "\005" source
              then let
                in case source
                of "\005trace" => (
                      REPL.set_trace true;
                      output cout packUnit () )
                 | "\005notrace" => (
                      REPL.set_trace false;
                      output cout packUnit () )
                 | "\005register_thy" => (
                      REPL.set_register_thy true;
                      output cout packUnit () )
                 | "\005no_register_thy" => (
                      REPL.set_register_thy false;
                      output cout packUnit () )
                 | "\005lex" => let
                           val src = read unpackString
                           val rets = REPL.lex_commands (!cfg) src
                        in output cout (packList (packPair (pos_packer, packString))) rets
                       end
                 | "\005lex'" => let
                           val src = read unpackString
                           val rets = REPL.fast_lex src
                        in output cout (packList (packPair (pos_packer, packString))) rets
                       end
                 | "\005plugin" => let
                           val thy = read unpackString
                           val name = read unpackString
                           val src = read unpackString
                           val [thy] = REPL.thy_loader NONE "HOL" [thy]
                           val plugin = (name, compile_plugin (Context.Theory thy) src)
                        in REPL.register_plugin plugin
                         ; output cout packUnit ()
                       end
                 | "\005unplugin" => let
                           val name = read unpackString
                        in REPL.delete_plugin name
                         ; output cout packUnit ()
                       end
                 | "\005record" => let
                           val name = read unpackString
                        in REPL.record_state name
                         ; output cout packUnit ()
                       end
                 | "\005clean_history" => let
                        in REPL.clean_state ()
                         ; output cout packUnit ()
                       end
                 | "\005rollback" => let
                           val name = read unpackString
                           val ret = REPL.rollback_state (!cfg) name
                        in output cout REPL_Serialize.command_output_packer ret
                       end
                 | "\005history" => let
                           val his = REPL.list_states' (!cfg) ()
                        in output cout (packPairList (packString, REPL_Serialize.command_output_packer)) his
                       end
                 | "\005sexpr_term" => let
                           val str = read unpackString
                           val (_, term) = REPL.parse_term str
                        in output cout REPL_Serialize.s_expression_packer term
                       end
                 | "\005fact" => let
                           val str = read unpackString
                           val (ctxt, thms) = REPL.retrieve_fact str
                        in output cout (packList packString)
                                       (map (REPL.trim_makrup o Syntax.string_of_term ctxt o Thm.prop_of) thms)
                       end
                 | "\005sexpr_fact" => let
                           val str = read unpackString
                           val (_, thms) = REPL.retrieve_fact str
                        in output cout (packList packString)
                                       (map (REPL_Serialize.s_expression o Thm.prop_of) thms)
                       end
                 | "\005hammer" => let
                           val timeout = read unpackInt
                           val proof = REPL.sledgehammer timeout
                        in output cout packString proof
                       end
                 | "\005context" => let
                           val s_expr = read unpackBool
                           val ctxt = REPL.get_ctxt ()
                           val state = REPL.get_context ()
                        in output cout (REPL_Serialize.pack_context s_expr (Context.Proof ctxt)) state
                       end
                 | "\005qualifier" => let
                           val qualifier = read unpackString
                           (*val {base_dir, ...} = !cfg *)
                           val _ = cfg := { thy_qualifier=qualifier,
                                            file = #file (!cfg),
                                            position_label = #position_label (!cfg),
                                            additional_libs = #additional_libs (!cfg),
                                            import_dir = #import_dir (!cfg),
                                            single_cmd_timeout = #single_cmd_timeout (!cfg),
                                            attributes = #attributes (!cfg) }
                        in output cout packUnit ()
                       end
                 | "\005session-of" => let
                           val path = read unpackString
                           val session = REPL_Aux.parse_session_name (Path.explode path)
                        in output cout (packOption packString) session
                       end
                 | "\005app" => let
                           val name = read unpackString
                        in case app_of name
                        of NONE => output cout packBool false
                         | SOME app => (
                              output cout packBool true
                            ; BinIO.StreamIO.flushOut cout
                            ; app (cin, cout))
                       end
                 | "\005ML" => let
                           val (thy,src) = read (unpackPair (unpackString,unpackString))
                           val [thy] = REPL.thy_loader NONE "HOL" [thy]
                        in run_ML (Context.Theory thy) src
                         ; output cout packBool true
                       end
                 | "\005load" => let
                           val (thy_qualifier, targets) =
                                read (unpackPair (unpackString, unpackList unpackString))
                           val thys = REPL.thy_loader NONE thy_qualifier targets
                        in output cout (packList packString) (map Context.theory_long_name thys)
                       end
                 | "\005file" => let
                           (*if use_cache, will find the nearest cached evaluation state to continue*)
                           val (raw_path, pos, timeout, cache_the_position, use_cache, attrs) =
                                  read (unpackTuple6 (
                                      unpackString,
                                      unpackOption (
                                        unpackPair (unpackInt, unpackInt)),
                                      unpackOption unpackInt,
                                      unpackBool,
                                      unpackBool,
                                      unpackList unpackString
                                  ))
                           val path = Path.explode raw_path
                           val session = REPL_Aux.parse_session_name path
                           val cfg = { thy_qualifier =
                                            (case session of SOME s => s
                                                           | _ => #thy_qualifier (!cfg)),
                                       file = SOME raw_path,
                                       position_label = NONE,
                                       additional_libs = #additional_libs (!cfg),
                                       import_dir = SOME (Path.dir path),
                                       single_cmd_timeout = #single_cmd_timeout (!cfg),
                                       attributes = attrs }
                           val file = Path.implode (Path.expand path)
                           val (src, ofs) =
                                    case pos
                                      of NONE => (File.read path, NONE)
                                       | SOME (l,c) =>
                                            let val src = File.read path
                                                val ofs = column_to_offset src (l,c)
                                             in (String.substring (src, 0, ofs), SOME ofs)
                                            end
                           val (snapshot, to_eval) =
                                case ofs
                                  of NONE => ("init", src)
                                   | SOME ofs =>
                                      if use_cache
                                      then case Symtab.lookup (Synchronized.value evaluation_cache) file
                                        of NONE => ("init", src)
                                         | SOME ofs_tab =>
                                            let exception Break
                                             in ( Inttab.fold (fn (k, v) => fn _ =>
                                                      if k <= ofs then SOME (k, v) else raise Break
                                                    ) ofs_tab NONE
                                                handle Break => NONE)
                                             |> (fn NONE => ("init", src)
                                                  | SOME (k, v) =>
                                                      (v, String.substring (src, k, size src - k)))
                                            end
                                      else ("init", src)
                           val errs = #errors (REPL.rollback_state_global cfg snapshot evaluation_cache_store)
                           val _ = REPL.set_base_dir (Path.dir path)
                           val errs = if to_eval = ""
                                      then errs
                                      else case timeout
                                        of NONE   =>
                                              REPL.collect_erros (REPL.RE cfg to_eval) @ errs
                                         | SOME t =>
                                            let val relaxed = Time.fromMilliseconds (t + 200)
                                                val strict = Time.fromMilliseconds t
                                                val (time, output) = Timing.timing (Timeout.apply relaxed (REPL.RE cfg)) to_eval
                                                val time' = #elapsed time
                                                val errs' = REPL.collect_erros output
                                             in if not (null errs') andalso time' > strict
                                               then raise Timeout.TIMEOUT time'
                                               else errs' @ errs
                                            end
                           val _ = REPL.reset_base_dir ()
                        in if null errs andalso cache_the_position andalso is_some ofs
                           then let
                                val name = "_" ^ string_of_int (evaluation_cache_counter ())
                             in REPL.record_state_global name evaluation_cache_store
                              ; Synchronized.change evaluation_cache (
                                  Symtab.map_default (file, Inttab.empty)
                                    (Inttab.update (the ofs, name)))
                            end
                           else ()
                         ; output cout (packList packString) errs
                       end
                 | "\005eval" => let
                           val (src, timeout, timeout_single_cmd, import_dir) =
                                  read (unpackTuple4 (
                                      unpackString,
                                      unpackOption unpackInt,
                                      unpackOption unpackInt,
                                      unpackOption unpackString
                                  ))
                           val cfg = { thy_qualifier = #thy_qualifier (!cfg),
                                       file = #file (!cfg),
                                       position_label = #position_label (!cfg),
                                       additional_libs = #additional_libs (!cfg),
                                       import_dir = Option.map Path.explode import_dir,
                                       single_cmd_timeout = Option.map Time.fromMilliseconds timeout_single_cmd,
                                       attributes = #attributes (!cfg) }
                           val timeout = Option.map Time.fromMilliseconds timeout
                           val ret = case timeout
                                       of NONE   => REPL.RE cfg src
                                        | SOME t => let
                                            val (elapsed, ret) = Timing.timing (Timeout.apply t (REPL.RE cfg)) src
                                            val ret' = if is_some (#error ret) andalso
                                                          String.isPrefix "Some error happens" (the (#error ret)) andalso
                                                          t <= #cpu elapsed
                                                       then raise Timeout.TIMEOUT (#cpu elapsed)
                                                       else ret
                                                       
                                             in ret'
                                            end
                         in doPack REPL_Serialize.command_outputs_packer ret cout
                       end
                 | "\005addlibs" => let
                           val libs = read (unpackList unpackString)
                        in cfg := { thy_qualifier = #thy_qualifier (!cfg),
                                    file = #file (!cfg),
                                    position_label = #position_label (!cfg),
                                    additional_libs = merge (op =) (#additional_libs (!cfg), libs),
                                    import_dir = #import_dir (!cfg),
                                    single_cmd_timeout = #single_cmd_timeout (!cfg),
                                    attributes = #attributes (!cfg) }
                         ; output cout packUnit ()
                       end
                 | "\005numcpu" => let
                           val num = Multithreading.max_threads ()
                        in output cout packInt num
                       end
                 | "\005cmd_timeout" => let
                           val time = read (unpackOption unpackInt)
                                   |> Option.map Time.fromMilliseconds
                        in cfg := { thy_qualifier = #thy_qualifier (!cfg),
                                    file = #file (!cfg),
                                    position_label = #position_label (!cfg),
                                    additional_libs = #additional_libs (!cfg),
                                    import_dir = #import_dir (!cfg),
                                    single_cmd_timeout = time,
                                    attributes = #attributes (!cfg) }
                         ; output cout packUnit ()
                       end
                 | "\005config" => let
                           val attrs = read (unpackList unpackString)
                        in REPL.declare attrs
                         ; output cout packUnit ()
                       end
                end handle REPL.REPL_fail E =>
                       output_err cout E
              else let
                val ret = REPL.RE (!cfg) source
                 in doPack REPL_Serialize.command_outputs_packer ret cout
                end )
              catch E =>
                    output_err cout (Runtime.exn_message E) \<close>
            end
          fun loop () =
            let val continue = Unsynchronized.ref true
             in while !continue do
                  if BinIO.StreamIO.endOfStream (!cin)
                  then continue := false
                  else ( iteration ()
                       ; BinIO.StreamIO.flushOut cout)
            end
       in Isabelle_Thread.fork (  Isabelle_Thread.params "REPL-worker"
                                |> Isabelle_Thread.interrupts )
                               (fn () =>
            let val id = REPL.init_repler base_dir_of_theories thy0
             in \<^try>\<open>
            let open MessagePackBinIO.Pack
             in Thread_Data.put sockets (SOME (cin, cout))
              ; REPL.record_state "init"
              ; Synchronized.change clients (Inttab.update (id, Isabelle_Thread.self ()))
              ; output cout (packPair (packInt, packInt))
                            (Value.parse_int (getenv_strict "REPL_PID"), id)
              ; BinIO.StreamIO.flushOut cout
              ; loop ()
            end finally (
                BinIO.StreamIO.closeOut cout
              ; BinIO.StreamIO.closeIn (!cin)
              ; Synchronized.change clients (Inttab.delete_safe id)
           ) \<close>
            end )
         ; ()
      end
      handle CONTINUE => () )
      finally
        Synchronized.change servers (Symtab.delete addr0) \<close> ))
  end

fun kill_server address =
  case Symtab.lookup (Synchronized.value servers) address
    of SOME thr => Isabelle_Thread.interrupt_thread thr
     | NONE => ()


end

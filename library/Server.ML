signature REPL_SEVER = sig

type address = string (*IP address:port*)

val startup : Path.T -> theory option -> address -> Isabelle_Thread.T
val kill_server : address -> unit

type App = (BinIO.StreamIO.instream * BinIO.StreamIO.outstream) -> BinIO.StreamIO.instream
val register_app : string -> App -> unit
val app_of : string -> App option

val socket_in_of  : unit -> BinIO.StreamIO.instream
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

type App = (BinIO.StreamIO.instream * BinIO.StreamIO.outstream) -> BinIO.StreamIO.instream
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

      exception BAD_CONN
   in writeln msg
    ; Output.physical_stdout msg
    ; Output.physical_stderr msg
    ; Isabelle_Thread.fork (  Isabelle_Thread.params ("REPL server " ^ addr0)
                           |> Isabelle_Thread.interrupts )  (fn () => (
      Synchronized.change servers (Symtab.update_new (addr0, Isabelle_Thread.self ()))
    ; \<^try>\<open> while true do (
      let val (conn,sender) = Socket.accept socket
          val (cin, cout) = make_streams conn

          val (version, cin) = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
          val _ = if version = "0.9.4" then ()
                  else (
                    output_err cout "The server is connected with a wrong version of the client.\n\
                             \Please run `pip install \"IsaREPL==0.9.4\" --force-reinstall` to update your client."
                  ; BinIO.StreamIO.flushOut cout
                  ; Socket.close conn
                  ; raise BAD_CONN)
          val _ = output cout MessagePackBinIO.Pack.packInt (Value.parse_int (getenv_strict "REPL_PID"))
          val _ = BinIO.StreamIO.flushOut cout

          val (thy_qualifier, cin) = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
          val thy_qualifier = if thy_qualifier = ""
                              then if default_session = "Main"
                                   then "HOL"
                                   else default_session
                              else thy_qualifier
          val cfg = Unsynchronized.ref { thy_qualifier = thy_qualifier,
                                         file = NONE,
                                         position_label = NONE,
                                         additional_libs = [],
                                         base_dir = base_dir_of_theories,
                                         overwrite = false }

          fun loop cin =
            if BinIO.StreamIO.endOfStream cin
            then ()
            else let open MessagePackBinIO.Unpack
                val (source, cin') = doUnpack unpackString cin
                val cin' = let open MessagePackBinIO.Pack in \<^try>\<open> (
                  if String.isPrefix "\005" source
                  then let
                    in case source
                    of "\005trace" => (
                          REPL.set_trace true;
                          output cout packUnit ();
                          cin')
                     | "\005notrace" => (
                          REPL.set_trace false;
                          output cout packUnit ();
                          cin')
                     | "\005register_thy" => (
                          REPL.set_register_thy true;
                          output cout packUnit ();
                          cin')
                     | "\005no_register_thy" => (
                          REPL.set_register_thy false;
                          output cout packUnit ();
                          cin')
                     | "\005lex" => let
                               val (src, cin'') = doUnpack unpackString cin'
                               val rets = REPL.lex_commands (!cfg) src
                               val _ = output cout (packList (packPair (pos_packer, packString))) rets
                            in cin''
                           end
                     | "\005lex'" => let
                               val (src, cin'') = doUnpack unpackString cin'
                               val rets = REPL.fast_lex src
                               val _ = output cout (packList (packPair (pos_packer, packString))) rets
                            in cin''
                           end
                     | "\005plugin" => let
                               val (thy, cin'') = doUnpack unpackString cin'
                               val (name, cin'') = doUnpack unpackString cin''
                               val (src, cin'') = doUnpack unpackString cin''
                               val [thy] = REPL.thy_loader "HOL" [thy]
                               val plugin = (name, compile_plugin (Context.Theory thy) src)
                               val _ = REPL.register_plugin plugin
                               val _ = output cout packUnit ()
                            in cin''
                           end
                     | "\005unplugin" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val _ = REPL.delete_plugin name
                               val _ = output cout packUnit ()
                            in cin''
                           end
                     | "\005record" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val _ = REPL.record_state name
                               val _ = output cout packUnit ()
                            in cin''
                           end
                     | "\005clean_history" => let
                               val _ = REPL.clean_state ()
                               val _ = output cout packUnit ()
                            in cin'
                           end
                     | "\005rollback" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val ret = REPL.rollback_state (!cfg) name
                               val _ = output cout REPL_Serialize.command_output_packer ret
                            in cin''
                           end
                     | "\005history" => let
                               val his = REPL.list_states' (!cfg) ()
                               val _ = output cout (packPairList (packString, REPL_Serialize.command_output_packer)) his
                            in cin'
                           end
                     | "\005sexpr_term" => let
                               val (str, cin'') = doUnpack unpackString cin'
                               val (_, term) = REPL.parse_term str
                               val _ = output cout REPL_Serialize.s_expression_packer term
                            in cin''
                           end
                     | "\005fact" => let
                               val (str, cin'') = doUnpack unpackString cin'
                               val (ctxt, thms) = REPL.retrieve_fact str
                               val _ = output cout (packList packString)
                                          (map (REPL.trim_makrup o Syntax.string_of_term ctxt o Thm.prop_of) thms)
                            in cin''
                           end
                     | "\005sexpr_fact" => let
                               val (str, cin'') = doUnpack unpackString cin'
                               val (_, thms) = REPL.retrieve_fact str
                               val _ = output cout (packList packString)
                                          (map (REPL_Serialize.s_expression o Thm.prop_of) thms)
                            in cin''
                           end
                     | "\005hammer" => let
                               val (timeout, cin'') = doUnpack unpackInt cin'
                               val proof = REPL.sledgehammer timeout
                               val _ = output cout packString proof
                            in cin''
                           end
                     | "\005context" => let
                               val (s_expr, cin'') = doUnpack unpackBool cin'
                               val ctxt = REPL.get_ctxt ()
                               val state = REPL.get_context ()
                               val _ = output cout (REPL_Serialize.pack_context s_expr (Context.Proof ctxt)) state
                            in cin''
                           end
                     | "\005qualifier" => let
                               val (qualifier, cin'') = doUnpack unpackString cin'
                               (*val {base_dir, ...} = !cfg *)
                               val _ = cfg := { thy_qualifier=qualifier,
                                                file = #file (!cfg),
                                                position_label = #position_label (!cfg),
                                                additional_libs = #additional_libs (!cfg),
                                                base_dir = #base_dir (!cfg),
                                                overwrite = #overwrite (!cfg)}
                               val _ = output cout packUnit ()
                            in cin''
                           end
                     | "\005session-of" => let
                               val (path, cin'') = doUnpack unpackString cin'
                               val session = REPL_Aux.parse_session_name (Path.explode path)
                               val _ = output cout (packOption packString) session
                            in cin''
                           end
                     | "\005app" => let
                               val (name, cin'') = doUnpack unpackString cin'
                            in case app_of name
                            of NONE => (output cout packBool false; cin'')
                             | SOME app => (
                                  output cout packBool true
                                ; BinIO.StreamIO.flushOut cout
                                ; app (cin'', cout))
                           end
                     | "\005ML" => let
                               val ((thy,src), cin'') = doUnpack (unpackPair (unpackString,unpackString)) cin'
                               val [thy] = REPL.thy_loader "HOL" [thy]
                            in run_ML (Context.Theory thy) src
                             ; output cout packBool true
                             ; cin''
                           end
                     | "\005load" => let
                               val ((thy_qualifier, targets), cin'') =
                                    doUnpack (unpackPair (unpackString, unpackList unpackString)) cin'
                               val thys = REPL.thy_loader thy_qualifier targets
                            in output cout (packList packString) (map Context.theory_long_name thys)
                             ; cin''
                           end
                     | "\005file" => let
                               val ((raw_path, pos, timeout), cin'') =
                                      doUnpack (unpackTuple3 (
                                          unpackString,
                                          unpackOption (
                                            unpackPair (unpackInt, unpackInt)),
                                          unpackOption unpackInt
                                      )) cin'
                               val path = Path.explode raw_path
                               val session = REPL_Aux.parse_session_name path
                               val cfg = case session
                                           of SOME s => { thy_qualifier = s,
                                                          file = SOME raw_path,
                                                          position_label = NONE,
                                                          additional_libs = #additional_libs (!cfg),
                                                          base_dir = #base_dir (!cfg),
                                                          overwrite = #overwrite (!cfg)}
                                            | _ => !cfg
                               val src = case pos
                                           of NONE => File.read path
                                            | SOME (l,n) => let
                                                   val lns = File.read_lines path
                                                   fun take 0 (s::_) = [String.substring (s, 0, n)]
                                                     | take 0 [] = []
                                                     | take n (s::L) = s :: take (n-1) L
                                                     | take _ _ = raise General.Subscript
                                                in take (l-1) lns
                                                |> String.concatWith "\n"
                                               end
                               val timeout = Option.map Time.fromMilliseconds timeout
                               val ret = case timeout
                                           of NONE   => REPL.RE cfg src
                                            | SOME t => Timeout.apply t (REPL.RE cfg) src
                            in doPack REPL_Serialize.command_outputs_packer ret cout
                             ; cin''
                           end
                     | "\005eval" => let
                               val ((src, timeout), cin'') =
                                      doUnpack (unpackPair (
                                          unpackString,
                                          unpackOption unpackInt
                                      )) cin'
                               val timeout = Option.map Time.fromMilliseconds timeout
                               val ret = case timeout
                                           of NONE   => REPL.RE (!cfg) src
                                            | SOME t => Timeout.apply t (REPL.RE (!cfg)) src
                             in doPack REPL_Serialize.command_outputs_packer ret cout
                              ; cin''
                           end
                     | "\005addlibs" => let
                               val (libs, cin'') = doUnpack (unpackList unpackString) cin'
                            in cfg := { thy_qualifier = #thy_qualifier (!cfg),
                                        file = #file (!cfg),
                                        position_label = #position_label (!cfg),
                                        additional_libs = merge (op =) (#additional_libs (!cfg), libs),
                                        base_dir = #base_dir (!cfg),
                                        overwrite = #overwrite (!cfg)}
                             ; output cout packUnit ()
                             ; cin''
                           end
                     | "\005numcpu" => let
                               val num = Multithreading.max_threads ()
                            in output cout packInt num
                             ; cin'
                           end
                    end handle REPL.REPL_fail E => (
                           output_err cout E
                         ; cin')
                  else let
                    val ret = REPL.RE (!cfg) source
                     in doPack REPL_Serialize.command_outputs_packer ret cout
                      ; cin'
                    end )
                  catch E => (
                        output_err cout (Runtime.exn_message E)
                      ; cin') \<close>
                  end
                val _ = BinIO.StreamIO.flushOut cout
             in loop cin'
            end
       in Isabelle_Thread.fork (  Isabelle_Thread.params "REPL-worker"
                                |> Isabelle_Thread.interrupts )
                               (fn () => ( REPL.init_repler base_dir_of_theories thy0
                                         ; Thread_Data.put sockets (SOME (cin, cout))
                                         ; loop cin ))
         ; ()
      end
      handle BAD_CONN => () )
      finally
        Synchronized.change servers (Symtab.delete addr0) \<close> ))
  end

fun kill_server address =
  case Symtab.lookup (Synchronized.value servers) address
    of SOME thr => Isabelle_Thread.interrupt_thread thr
     | NONE => ()

end

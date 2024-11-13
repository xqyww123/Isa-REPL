signature REPL_SEVER = sig

type address = string (*IP address:port*)

val startup : Path.T -> theory option -> address -> Isabelle_Thread.T
val kill_server : address -> unit

end

val REPL_ML_sender_DO_NOT_OVERRIDE_ : REPL.collector option Unsynchronized.ref
      = Unsynchronized.ref NONE
val REPL_ML_sender_DO_NOT_OVERRIDE_locker_
      = Synchronized.var "REPL_ML_sender_DO_NOT_OVERRIDE_locker_" ()

structure REPL_Server : REPL_SEVER = struct

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

fun compile_ML ctxt source =
  let val pos = Position.make {
              line=1, offset=1, end_offset=1, props={label="", file="#REPL-ML", id=""}}
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


val session_ID_counter = Counter.make ()

val servers = Synchronized.var "REPL Servers" (Symtab.empty : Isabelle_Thread.T Symtab.table)

fun startup base_dir_of_theories thy0 addr0 =
  let val _ = if File.is_dir base_dir_of_theories
              then warning ("The base_dir_of_theories already exists. The shell may overwrite files.")
              else if File.exists base_dir_of_theories
              then error ("The base_dir_of_theories must be a directory : " ^ File.standard_path base_dir_of_theories)
              else OS.FileSys.mkDir (File.standard_path base_dir_of_theories)

      val ctxt = case thy0 of SOME some => Context.Theory some
                            | NONE => Context.the_generic_context ()

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
   in writeln msg
    ; Output.physical_stdout msg
    ; Output.physical_stderr msg
    ; Isabelle_Thread.fork (  Isabelle_Thread.params ("REPL server " ^ addr0)
                           |> Isabelle_Thread.interrupts )  (fn () => (
      Synchronized.change servers (Symtab.update_new (addr0, Isabelle_Thread.self ()))
    ; \<^try>\<open> while true do 
      let val (conn,sender) = Socket.accept socket
          val (cin, cout) = make_streams conn

          val wid = session_ID_counter ()
          val base_dir = Path.append base_dir_of_theories (Path.basic (string_of_int wid))
          val _ = if File.is_dir base_dir
                  then ()
                  else ( if File.exists base_dir then File.rm base_dir else ();
                         OS.FileSys.mkDir (File.platform_path base_dir) )

          val (thy_qualifier, cin) = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
          val cfg = {base_dir=base_dir, thy_qualifier=thy_qualifier}

          fun loop cin =
            if BinIO.StreamIO.endOfStream cin
            then ()
            else let open MessagePackBinIO.Unpack
                val (source, cin') = doUnpack unpackString cin
                val cin' = let open MessagePackBinIO.Pack in \<^try>\<open> (
                  if String.isPrefix "\005" source
                  then let
                       fun output pack x =
                          doPack (packPair (pack, packUnit)) (x, ()) cout
                    in case source
                    of "\005trace" => (
                          REPL.set_trace true;
                          output packUnit ();
                          cin')
                     | "\005notrace" => (
                          REPL.set_trace false;
                          output packUnit ();
                          cin')
                     | "\005lex" => let
                               val (src, cin'') = doUnpack unpackString cin'
                               val rets = REPL.lex_commands cfg src
                               val _ = output (packList packString) rets
                            in cin''
                           end
                     | "\005plugin" => let
                               val ((name, src), cin'') = doUnpack (unpackPair (unpackString, unpackString)) cin'
                               val plugin = (name, compile_ML ctxt src)
                               val _ = REPL.register_plugin plugin
                               val _ = output packUnit ()
                            in cin''
                           end
                     | "\005unplugin" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val _ = REPL.delete_plugin name
                               val _ = output packUnit ()
                            in cin''
                           end
                     | "\005record" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val _ = REPL.record_state name
                               val _ = output packUnit ()
                            in cin''
                           end
                     | "\005clean_history" => let
                               val _ = REPL.clean_state ()
                               val _ = output packUnit ()
                            in cin'
                           end
                     | "\005rollback" => let
                               val (name, cin'') = doUnpack unpackString cin'
                               val ret = REPL.rollback_state name
                               val _ = output REPL_Serialize.command_output_packer ret
                            in cin''
                           end
                     | "\005history" => let
                               val his = REPL.list_states' ()
                               val _ = output (packPairList (packString, REPL_Serialize.command_output_packer)) his
                            in cin'
                           end
                    end handle REPL.REPL_fail E => (
                           doPack (packPair (packUnit, packString)) ((), E) cout ;
                           cin')
                  else let
                    val ret = REPL.RE cfg source
                     in doPack REPL_Serialize.command_outputs_packer ret cout
                      ; cin'
                    end )
                  catch E => (
                      doPack (packPair (packUnit, packString))
                             ((), REPL.trim_makrup (Runtime.exn_message E)) cout ;
                      cin') \<close>
                  end
                val _ = BinIO.StreamIO.flushOut cout
             in loop cin'
            end
       in  Isabelle_Thread.fork (  Isabelle_Thread.params "REPL-worker"
                                |> Isabelle_Thread.interrupts )
                               (fn () => ( REPL.init_repler wid thy0
                                         ; loop cin  ))
      end
      finally
        Synchronized.change servers (Symtab.delete addr0) \<close> ))
  end

fun kill_server address =
  case Symtab.lookup (Synchronized.value servers) address
    of SOME thr => Isabelle_Thread.interrupt_thread thr
     | NONE => ()

end
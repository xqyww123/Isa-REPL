signature REPL_SEVER = sig

type address = string (*IP address:port*)

val startup : Path.T -> theory option -> address -> Thread.thread
val kill_server : address -> unit

end

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

val session_ID_counter = Counter.make ()

val servers = Synchronized.var "REPL Servers" (Symtab.empty : Thread.thread Symtab.table)

fun startup base_dir_of_theories thy addr0 =
  let val _ = if File.is_dir base_dir_of_theories
              then warning ("The base_dir_of_theories already exists. The shell may overwrite files.")
              else if File.exists base_dir_of_theories
              then error ("The base_dir_of_theories must be a directory : " ^ File.standard_path base_dir_of_theories)
              else OS.FileSys.mkDir (File.standard_path base_dir_of_theories)

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
    ; Isabelle_Thread.fork {name="REPL server " ^ addr0, stack_limit=NONE, interrupts=true} (fn () => (
      Synchronized.change servers (Symtab.update_new (addr0, Thread.self ()))
    ; while true do
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

          fun loop cin =
            if BinIO.StreamIO.endOfStream cin
            then ()
            else let
                val (source, cin') = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
                val _ = let open MessagePackBinIO.Pack in
                  if String.isPrefix "\005" source
                  then case source
                    of "\005trace" => (
                          REPL.set_trace true;
                          doPack packBool true cout)
                     | "\005notrace" => (
                          REPL.set_trace false;
                          doPack packBool true cout)
                  else let
                    val ret = REPL.RE {base_dir=base_dir, thy_qualifier=thy_qualifier} source
                     in doPack REPL_Serialize.command_outputs_packer ret cout
                    end
                  end
                val _ = BinIO.StreamIO.flushOut cout
             in loop cin'
            end
       in Isabelle_Thread.fork {name="REPL-worker", stack_limit=NONE, interrupts=true}
                               (fn () => ( REPL.init_repler wid thy
                                         ; loop cin ))
      end
        handle E => (
        Synchronized.change servers (Symtab.delete addr0) ;
        Exn.reraise E) ))
  end

fun kill_server address =
  case Symtab.lookup (Synchronized.value servers) address
    of SOME thr => Isabelle_Thread.interrupt_unsynchronized thr
     | NONE => ()

end
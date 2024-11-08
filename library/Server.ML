signature REPL_SEVER = sig

val startup : theory option -> string (*listening address:port*) -> unit

end

structure REPL_Server : REPL_SEVER = struct

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

val _ = Multithreading.parallel_proofs := 0

fun startup thy addr0 =
  let val socket: Socket.passive INetSock.stream_sock = INetSock.TCP.socket ()
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
    ; while true do
      let val (conn,sender) = Socket.accept socket
          val (cin, cout) = make_streams conn
          fun loop cin =
            if BinIO.StreamIO.endOfStream cin
            then ()
            else let
                val (source, cin') = MessagePackBinIO.Unpack.doUnpack
                                          (MessagePackBinIO.Unpack.unpackString) cin
                val ret = REPL.RE source
                val _ = MessagePackBinIO.Pack.doPack REPL_Serialize.command_outputs_packer ret cout
                val _ = BinIO.StreamIO.flushOut cout
             in loop cin'
            end
       in Isabelle_Thread.fork {name="REPL-worker", stack_limit=NONE, interrupts=true}
                               (fn () => ( REPL.init_repler thy
                                         ; loop cin ))
      end
  end

end
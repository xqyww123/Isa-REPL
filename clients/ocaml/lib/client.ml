(** Isabelle REPL Client *)

open Exceptions

(** Client version *)
let version = "0.13.0"

(** Message types *)
type message_type = NORMAL | TRACING | WARNING

let message_type_of_int = function
  | 0 -> NORMAL
  | 1 -> TRACING
  | 2 -> WARNING
  | _ -> NORMAL

(** Output message *)
type message = {
  msg_type : message_type;
  content : string;
}

(** State flags *)
type state_flags = {
  is_toplevel : bool;
  is_theory : bool;
  is_proof : bool;
  has_goal : bool;
}

(** Command output *)
type command_output = {
  command_name : string;
  output : message list;
  latex : string option;
  flags : state_flags;
  level : int;
  state : string;
  plugin_output : Msgpck.t;
  errors : string list;
}

(** Evaluation result *)
type eval_result = {
  outputs : command_output list option;
  error : string option;
}

(** Client connection *)
type t = {
  addr : string;
  sock : Unix.file_descr;
  cin : in_channel;
  cout : out_channel;
  pid : int;
  client_id : int;
  mutable closed : bool;
}

(** Global client registry *)
let clients : (int, t) Hashtbl.t = Hashtbl.create 10

(** Write msgpack to out_channel *)
let write_msgpack oc msg =
  let buf = Buffer.create 1024 in
  let _ = Msgpck.StringBuf.write buf msg in
  output_string oc (Buffer.contents buf);
  flush oc

(** Read msgpack from in_channel *)
let read_msgpack ic =
  (* Read all available data into a buffer *)
  let buf = Buffer.create 4096 in
  let chunk_size = 4096 in
  let chunk = Bytes.create chunk_size in

  (* Read at least some data *)
  let n = input ic chunk 0 1 in
  if n = 0 then raise End_of_file;
  Buffer.add_subbytes buf chunk 0 n;

  (* Try to parse, if we need more data, read more *)
  let rec try_parse () =
    let str = Buffer.contents buf in
    try
      let (bytes_read, msg) = Msgpck.StringBuf.read str in
      if bytes_read < String.length str then
        (* We read more than needed, that's ok *)
        msg
      else
        msg
    with Invalid_argument _ ->
      (* Need more data *)
      let n = input ic chunk 0 chunk_size in
      if n = 0 then raise End_of_file;
      Buffer.add_subbytes buf chunk 0 n;
      try_parse ()
  in
  try_parse ()

(** Parse control message *)
let parse_control msg =
  match msg with
  | Msgpck.List [result; Msgpck.Nil] -> result
  | Msgpck.List [_; Msgpck.String err] -> raise (REPLFail err)
  | Msgpck.List [_; Msgpck.Bytes err] ->
      raise (REPLFail err)
  | _ -> raise (REPLFail "Invalid control message format")

(** Check if client is alive *)
let check_alive client =
  if client.closed then
    raise (REPLFail (Printf.sprintf "Client %d is dead or closed" client.client_id))

(** Create a new client and connect to the server *)
let create ?(timeout=3600.0) addr thy_qualifier =
  let parse_addr s =
    match String.split_on_char ':' s with
    | [host; port] -> (host, int_of_string port)
    | _ -> raise (Invalid_argument "Invalid address format, expected host:port")
  in
  let (host, port) = parse_addr addr in

  (* Create socket with timeout *)
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float sock Unix.SO_RCVTIMEO timeout;
  Unix.setsockopt_float sock Unix.SO_SNDTIMEO timeout;

  let host_entry = Unix.gethostbyname host in
  let server_addr = Unix.ADDR_INET (host_entry.Unix.h_addr_list.(0), port) in
  Unix.connect sock server_addr;

  let cin = Unix.in_channel_of_descr sock in
  let cout = Unix.out_channel_of_descr sock in

  (* Send version and qualifier *)
  write_msgpack cout (Msgpck.of_string version);
  write_msgpack cout (Msgpck.of_string thy_qualifier);

  (* Receive response *)
  let response = read_msgpack cin in

  let (pid, client_id) = match parse_control response with
    | Msgpck.List [Msgpck.Int pid; Msgpck.Int cid] -> (pid, cid)
    | Msgpck.List [Msgpck.Int32 pid; Msgpck.Int32 cid] ->
        (Int32.to_int pid, Int32.to_int cid)
    | Msgpck.List [Msgpck.Int64 pid; Msgpck.Int64 cid] ->
        (Int64.to_int pid, Int64.to_int cid)
    | Msgpck.List [Msgpck.Uint32 pid; Msgpck.Uint32 cid] ->
        (Int32.to_int pid, Int32.to_int cid)
    | Msgpck.List [Msgpck.Uint64 pid; Msgpck.Uint64 cid] ->
        (Int64.to_int pid, Int64.to_int cid)
    | _ -> raise (REPLFail "Invalid handshake response")
  in

  let client = {
    addr;
    sock;
    cin;
    cout;
    pid;
    client_id;
    closed = false;
  } in
  Hashtbl.add clients client_id client;
  client

(** Close the client connection *)
let close client =
  if not client.closed then begin
    client.closed <- true;
    (try close_in_noerr client.cin with _ -> ());
    (try close_out_noerr client.cout with _ -> ());
    (try Unix.close client.sock with _ -> ());
    Hashtbl.remove clients client.client_id
  end

(** Send a message and wait for response *)
let send_command client cmd =
  check_alive client;
  write_msgpack client.cout cmd;
  parse_control (read_msgpack client.cin)

(** Evaluate source code *)
let eval ?timeout ?cmd_timeout ?import_dir client source =
  let msg = match timeout, cmd_timeout, import_dir with
    | None, None, None -> Msgpck.of_string source
    | _ ->
        let timeout_v = match timeout with Some t -> Msgpck.of_int t | None -> Msgpck.Nil in
        let cmd_timeout_v = match cmd_timeout with Some t -> Msgpck.of_int t | None -> Msgpck.Nil in
        let import_dir_v = match import_dir with Some d -> Msgpck.of_string d | None -> Msgpck.Nil in
        Msgpck.of_list [
          Msgpck.of_string "\x05eval";
          Msgpck.of_list [Msgpck.of_string source; timeout_v; cmd_timeout_v; import_dir_v]
        ]
  in
  send_command client msg

(** Set trace mode *)
let set_trace client trace =
  let msg = Msgpck.of_string (if trace then "\x05trace" else "\x05notrace") in
  let _ = send_command client msg in
  ()

(** Set register theory flag *)
let set_register_thy client value =
  let msg = Msgpck.of_string (if value then "\x05register_thy" else "\x05no_register_thy") in
  let _ = send_command client msg in
  ()

(** Lex source code into commands *)
let lex client source =
  write_msgpack client.cout (Msgpck.of_string "\x05lex");
  write_msgpack client.cout (Msgpck.of_string source);
  let response = read_msgpack client.cin in
  parse_control response

(** Fast lex (using system keywords only) *)
let fast_lex client source =
  write_msgpack client.cout (Msgpck.of_string "\x05lex'");
  write_msgpack client.cout (Msgpck.of_string source);
  let response = read_msgpack client.cin in
  parse_control response

(** Lex a file *)
let lex_file client file =
  write_msgpack client.cout (Msgpck.of_string "\x05lex_file");
  write_msgpack client.cout (Msgpck.of_string file);
  let response = read_msgpack client.cin in
  parse_control response

(** Record current state *)
let record_state client name =
  write_msgpack client.cout (Msgpck.of_string "\x05record");
  write_msgpack client.cout (Msgpck.of_string name);
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Clean history *)
let clean_history client =
  write_msgpack client.cout (Msgpck.of_string "\x05clean_history");
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Rollback to a recorded state *)
let rollback client name =
  write_msgpack client.cout (Msgpck.of_string "\x05rollback");
  write_msgpack client.cout (Msgpck.of_string name);
  let response = read_msgpack client.cin in
  parse_control response

(** Get history of recorded states *)
let history client =
  write_msgpack client.cout (Msgpck.of_string "\x05history");
  let response = read_msgpack client.cin in
  parse_control response

(** Install a plugin *)
let plugin client ~name ~ml_code ?(thy="Isa_REPL.Isa_REPL") () =
  write_msgpack client.cout (Msgpck.of_string "\x05plugin");
  write_msgpack client.cout (Msgpck.of_string thy);
  write_msgpack client.cout (Msgpck.of_string name);
  write_msgpack client.cout (Msgpck.of_string ml_code);
  let response = read_msgpack client.cin in
  parse_control response

(** Remove a plugin *)
let unplugin client name =
  write_msgpack client.cout (Msgpck.of_string "\x05unplugin");
  write_msgpack client.cout (Msgpck.of_string name);
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Convert term to S-expression *)
let sexpr_term client term =
  write_msgpack client.cout (Msgpck.of_string "\x05sexpr_term");
  write_msgpack client.cout (Msgpck.of_string term);
  let response = read_msgpack client.cin in
  parse_control response

(** Retrieve facts *)
let fact client names =
  write_msgpack client.cout (Msgpck.of_string "\x05fact");
  write_msgpack client.cout (Msgpck.of_string names);
  let response = read_msgpack client.cin in
  parse_control response

(** Retrieve facts as S-expressions *)
let sexpr_fact client names =
  write_msgpack client.cout (Msgpck.of_string "\x05sexpr_fact");
  write_msgpack client.cout (Msgpck.of_string names);
  let response = read_msgpack client.cin in
  parse_control response

(** Invoke sledgehammer *)
let hammer client timeout =
  write_msgpack client.cout (Msgpck.of_string "\x05hammer");
  write_msgpack client.cout (Msgpck.of_int timeout);
  let response = read_msgpack client.cin in
  parse_control response

(** Get proof context *)
let context ?(pp="pretty") client =
  write_msgpack client.cout (Msgpck.of_string "\x05context");
  write_msgpack client.cout (Msgpck.of_string pp);
  let response = read_msgpack client.cin in
  parse_control response

(** Set theory qualifier *)
let set_thy_qualifier client thy_qualifier =
  write_msgpack client.cout (Msgpck.of_string "\x05qualifier");
  write_msgpack client.cout (Msgpck.of_string thy_qualifier);
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Get session name of a file *)
let session_name_of client path =
  write_msgpack client.cout (Msgpck.of_string "\x05session-of");
  write_msgpack client.cout (Msgpck.of_string path);
  let response = read_msgpack client.cin in
  parse_control response

(** Load theories *)
let load_theory client ?(thy_qualifier="") targets =
  write_msgpack client.cout (Msgpck.of_string "\x05load");
  write_msgpack client.cout (Msgpck.of_list [
    Msgpck.of_string thy_qualifier;
    Msgpck.of_list (List.map Msgpck.of_string targets)
  ]);
  let response = read_msgpack client.cin in
  parse_control response

(** Evaluate a file *)
let file ?(line=(-1)) ?(column=0) ?timeout ?(attrs=[])
         ?(cache_position=false) ?(use_cache=false) client path =
  let pos = if line >= 0 then Msgpck.of_list [Msgpck.of_int line; Msgpck.of_int column] else Msgpck.Nil in
  let timeout_v = match timeout with Some t -> Msgpck.of_int t | None -> Msgpck.Nil in
  write_msgpack client.cout (Msgpck.of_string "\x05file");
  write_msgpack client.cout (Msgpck.of_list [
    Msgpck.of_string path;
    pos;
    timeout_v;
    Msgpck.of_bool cache_position;
    Msgpck.of_bool use_cache;
    Msgpck.of_list (List.map Msgpck.of_string attrs)
  ]);
  let response = read_msgpack client.cin in
  let errs = parse_control response in
  match errs with
  | Msgpck.List [] -> ()
  | Msgpck.List errs ->
      let err_strs = List.map (function
        | Msgpck.String s -> s
        | Msgpck.Bytes b -> b
        | _ -> ""
      ) errs in
      raise (REPLFail (String.concat "\n" err_strs))
  | _ -> ()

(** Clean file evaluation cache *)
let clean_cache client =
  write_msgpack client.cout (Msgpck.of_string "\x05clean_cache");
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Add libraries *)
let add_lib client libs =
  write_msgpack client.cout (Msgpck.of_string "\x05addlibs");
  write_msgpack client.cout (Msgpck.of_list (List.map Msgpck.of_string libs));
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Get number of processors *)
let num_processor client =
  write_msgpack client.cout (Msgpck.of_string "\x05numcpu");
  let response = read_msgpack client.cin in
  match parse_control response with
  | Msgpck.Int n when n > 0 -> n
  | Msgpck.Int _ -> 1
  | _ -> 1

(** Set command timeout *)
let set_cmd_timeout client timeout =
  write_msgpack client.cout (Msgpck.of_string "\x05cmd_timeout");
  write_msgpack client.cout (match timeout with Some t -> Msgpck.of_int t | None -> Msgpck.Nil);
  let response = read_msgpack client.cin in
  let _ = parse_control response in
  ()

(** Kill the server *)
let kill client =
  Unix.kill client.pid Sys.sigkill

(** Test server connectivity *)
let test_server ?(timeout=60.0) addr =
  let (host, port) =
    match String.split_on_char ':' addr with
    | [h; p] -> (h, int_of_string p)
    | _ -> raise (Invalid_argument "Invalid address format")
  in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float sock Unix.SO_RCVTIMEO timeout;
  Unix.setsockopt_float sock Unix.SO_SNDTIMEO timeout;
  let host_entry = Unix.gethostbyname host in
  let server_addr = Unix.ADDR_INET (host_entry.Unix.h_addr_list.(0), port) in
  Unix.connect sock server_addr;
  let cout = Unix.out_channel_of_descr sock in
  let cin = Unix.in_channel_of_descr sock in
  write_msgpack cout (Msgpck.of_string "heartbeat");
  let response = read_msgpack cin in
  let _ = parse_control response in
  Unix.close sock

(** Kill a client on the server *)
let kill_client ?(timeout=60.0) addr client_id =
  let (host, port) =
    match String.split_on_char ':' addr with
    | [h; p] -> (h, int_of_string p)
    | _ -> raise (Invalid_argument "Invalid address format")
  in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt_float sock Unix.SO_RCVTIMEO timeout;
  Unix.setsockopt_float sock Unix.SO_SNDTIMEO timeout;
  let host_entry = Unix.gethostbyname host in
  let server_addr = Unix.ADDR_INET (host_entry.Unix.h_addr_list.(0), port) in
  Unix.connect sock server_addr;
  let cout = Unix.out_channel_of_descr sock in
  let cin = Unix.in_channel_of_descr sock in
  write_msgpack cout (Msgpck.of_string ("kill " ^ string_of_int client_id));
  let response = read_msgpack cin in
  match parse_control response with
  | Msgpck.Bool b -> b
  | _ -> false

(** OCaml client library for Isabelle REPL

    This library provides an OCaml interface to connect to and interact with
    Isabelle REPL servers. It supports evaluation of Isabelle code, lexing,
    state management, and various other REPL operations.

    Basic usage:
    {[
      let client = Isa_repl.create "localhost:9000" "HOL" in
      let result = Isa_repl.eval client "lemma \"True\" by auto" in
      Isa_repl.close client
    ]}
*)

(** {1 Modules} *)

module Position : sig
  (** Position in an Isabelle file *)
  type t = {
    line : int;
    column : int;
    file : string;
  }

  val create : line:int -> column:int -> file:string -> t
  val to_string : t -> string
  val from_string : string -> t option
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val hash : t -> int
end

module Symbols : sig
  (** Isabelle symbol management *)
  type symbol_table = (string, string) Hashtbl.t
  type symbol_cache = {
    symbols : symbol_table;
    reverse_symbols : symbol_table;
  }

  val get_symbols : unit -> symbol_table
  val get_reverse_symbols : unit -> symbol_table
  val pretty_unicode : string -> string
  val unicode_of_ascii : string -> string
  val ascii_of_unicode : string -> string
end

module Exceptions : sig
  exception REPLFail of string
end

module Msgpck = Msgpck

module Client : sig
  (** Message types in output *)
  type message_type = NORMAL | TRACING | WARNING

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

  (** {2 Connection Management} *)

  val create : ?timeout:float -> string -> string -> t
  (** [create ~timeout addr thy_qualifier] creates a new client connection.

      @param addr Server address in format "host:port"
      @param thy_qualifier Session name for resolving theory names
      @param timeout Connection timeout in seconds (default: 3600.0)
      @return A new client instance
  *)

  val close : t -> unit
  (** Close the client connection *)

  val test_server : ?timeout:float -> string -> unit
  (** Test if server is accessible *)

  val kill_client : ?timeout:float -> string -> int -> bool
  (** Kill a specific client on the server *)

  (** {2 Code Evaluation} *)

  val eval : ?timeout:int -> ?cmd_timeout:int -> ?import_dir:string ->
             t -> string -> Msgpck.t
  (** Evaluate Isabelle source code *)

  val file : ?line:int -> ?column:int -> ?timeout:int -> ?attrs:string list ->
             ?cache_position:bool -> ?use_cache:bool -> t -> string -> unit
  (** Evaluate an Isabelle file *)

  (** {2 Lexing} *)

  val lex : t -> string -> Msgpck.t
  (** Split source into command sequence *)

  val fast_lex : t -> string -> Msgpck.t
  (** Fast lex using system keywords only *)

  val lex_file : t -> string -> Msgpck.t
  (** Lex an Isabelle file *)

  (** {2 State Management} *)

  val record_state : t -> string -> unit
  (** Record current evaluation state *)

  val rollback : t -> string -> Msgpck.t
  (** Rollback to recorded state *)

  val history : t -> Msgpck.t
  (** Get history of recorded states *)

  val clean_history : t -> unit
  (** Clean all recorded states *)

  val clean_cache : t -> unit
  (** Clean file evaluation cache *)

  (** {2 Settings} *)

  val set_trace : t -> bool -> unit
  (** Enable/disable output tracing *)

  val set_register_thy : t -> bool -> unit
  (** Enable/disable theory registration *)

  val set_thy_qualifier : t -> string -> unit
  (** Change theory qualifier *)

  val set_cmd_timeout : t -> int option -> unit
  (** Set command timeout *)

  (** {2 Plugins} *)

  val plugin : t -> name:string -> ml_code:string -> ?thy:string -> unit -> Msgpck.t
  (** Install a user plugin *)

  val unplugin : t -> string -> unit
  (** Remove an installed plugin *)

  (** {2 Term and Fact Operations} *)

  val sexpr_term : t -> string -> Msgpck.t
  (** Parse term to S-expression *)

  val fact : t -> string -> Msgpck.t
  (** Retrieve facts *)

  val sexpr_fact : t -> string -> Msgpck.t
  (** Retrieve facts as S-expressions *)

  val context : ?pp:string -> t -> Msgpck.t
  (** Get proof context *)

  (** {2 Automation} *)

  val hammer : t -> int -> Msgpck.t
  (** Invoke Sledgehammer *)

  (** {2 Theory Management} *)

  val session_name_of : t -> string -> Msgpck.t
  (** Get session name of a file *)

  val load_theory : t -> ?thy_qualifier:string -> string list -> Msgpck.t
  (** Load theories *)

  val add_lib : t -> string list -> unit
  (** Add additional libraries *)

  (** {2 Utilities} *)

  val num_processor : t -> int
  (** Get number of available processors *)

  val kill : t -> unit
  (** Kill the server process *)
end

(** {1 Convenient Type Aliases} *)

type position = Position.t
type client = Client.t

exception REPLFail of string

(** {1 Client Operations} *)

val create : ?timeout:float -> string -> string -> client
val close : client -> unit
val eval : ?timeout:int -> ?cmd_timeout:int -> ?import_dir:string ->
           client -> string -> Msgpck.t
val lex : client -> string -> Msgpck.t
val fast_lex : client -> string -> Msgpck.t
val lex_file : client -> string -> Msgpck.t
val set_trace : client -> bool -> unit
val set_register_thy : client -> bool -> unit
val record_state : client -> string -> unit
val clean_history : client -> unit
val rollback : client -> string -> Msgpck.t
val history : client -> Msgpck.t
val plugin : client -> name:string -> ml_code:string -> ?thy:string -> unit -> Msgpck.t
val unplugin : client -> string -> unit
val sexpr_term : client -> string -> Msgpck.t
val fact : client -> string -> Msgpck.t
val sexpr_fact : client -> string -> Msgpck.t
val hammer : client -> int -> Msgpck.t
val context : ?pp:string -> client -> Msgpck.t
val set_thy_qualifier : client -> string -> unit
val session_name_of : client -> string -> Msgpck.t
val load_theory : client -> ?thy_qualifier:string -> string list -> Msgpck.t
val file : ?line:int -> ?column:int -> ?timeout:int -> ?attrs:string list ->
           ?cache_position:bool -> ?use_cache:bool -> client -> string -> unit
val clean_cache : client -> unit
val add_lib : client -> string list -> unit
val num_processor : client -> int
val set_cmd_timeout : client -> int option -> unit
val kill : client -> unit
val test_server : ?timeout:float -> string -> unit
val kill_client : ?timeout:float -> string -> int -> bool

(** {1 Symbol Operations} *)

val pretty_unicode : string -> string
(** Convert ASCII notation to Unicode *)

val unicode_of_ascii : string -> string
(** Same as [pretty_unicode] *)

val ascii_of_unicode : string -> string
(** Convert Unicode to ASCII notation *)

val get_symbols : unit -> Symbols.symbol_table
(** Get symbol mapping table *)

val get_reverse_symbols : unit -> Symbols.symbol_table
(** Get reverse symbol mapping table *)

(** {1 Position Operations} *)

val position_create : line:int -> column:int -> file:string -> position
val position_to_string : position -> string
val position_from_string : string -> position option

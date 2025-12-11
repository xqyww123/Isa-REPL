(** OCaml client library for Isabelle REPL *)

(** Re-export main modules *)
module Position = Position
module Symbols = Symbols
module Client = Client
module Exceptions = Exceptions
module Msgpck = Msgpck

(** Re-export commonly used types and functions *)
type position = Position.t
type client = Client.t

exception REPLFail of string

(** Client operations *)
let create = Client.create
let close = Client.close
let eval = Client.eval
let lex = Client.lex
let fast_lex = Client.fast_lex
let lex_file = Client.lex_file
let set_trace = Client.set_trace
let set_register_thy = Client.set_register_thy
let record_state = Client.record_state
let clean_history = Client.clean_history
let rollback = Client.rollback
let history = Client.history
let plugin = Client.plugin
let unplugin = Client.unplugin
let sexpr_term = Client.sexpr_term
let fact = Client.fact
let sexpr_fact = Client.sexpr_fact
let hammer = Client.hammer
let context = Client.context
let set_thy_qualifier = Client.set_thy_qualifier
let session_name_of = Client.session_name_of
let load_theory = Client.load_theory
let file = Client.file
let clean_cache = Client.clean_cache
let add_lib = Client.add_lib
let num_processor = Client.num_processor
let set_cmd_timeout = Client.set_cmd_timeout
let kill = Client.kill
let test_server = Client.test_server
let kill_client = Client.kill_client

(** Symbol operations *)
let pretty_unicode = Symbols.pretty_unicode
let unicode_of_ascii = Symbols.unicode_of_ascii
let ascii_of_unicode = Symbols.ascii_of_unicode
let get_symbols = Symbols.get_symbols
let get_reverse_symbols = Symbols.get_reverse_symbols

(** Position operations *)
let position_create = Position.create
let position_to_string = Position.to_string
let position_from_string = Position.from_string

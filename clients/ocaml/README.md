# Isa-REPL OCaml Client

OCaml client library for connecting to and interacting with Isabelle REPL servers.

This is an OCaml translation of the Python client library from [Isa-REPL](https://github.com/xqyww123/Isa-REPL).

## Installation

### Dependencies

The library requires the following OCaml packages:
- `ocaml >= 4.14`
- `dune >= 3.0`
- `msgpack` - for MessagePack serialization
- `re` - for regular expressions

### Building from Source

```bash
cd clients/ocaml
dune build
dune install
```

## Usage

### Basic Example

```ocaml
open Isa_repl

(* Connect to an Isabelle REPL server *)
let client = create "localhost:9000" "HOL" in

(* Evaluate some Isabelle code *)
let result = eval client "theory Test imports Main begin end" in

(* Lex source code into commands *)
let commands = lex client "
  lemma example: \"True\"
    by auto
" in

(* Close the connection *)
close client
```

### Working with Files

```ocaml
open Isa_repl

let client = create "localhost:9000" "HOL" in

(* Evaluate a theory file *)
file client "/path/to/Theory.thy";

(* Evaluate up to a specific position *)
file ~line:10 ~column:5 client "/path/to/Theory.thy";

close client
```

### State Management

```ocaml
open Isa_repl

let client = create "localhost:9000" "HOL" in

(* Record current state *)
record_state client "checkpoint1";

(* Do some evaluation *)
let _ = eval client "lemma test: \"True\" by auto" in

(* Rollback to saved state *)
rollback client "checkpoint1";

(* Clean history *)
clean_history client;

close client
```

### Using Plugins

```ocaml
open Isa_repl

let client = create "localhost:9000" "HOL" in

let ml_code = {|
  fn st => (NONE, NONE)
|} in

plugin client ~name:"my_plugin" ~ml_code ();

(* Remove plugin *)
unplugin client "my_plugin";

close client
```

### Symbol Conversion

```ocaml
open Isa_repl

(* Convert ASCII notation to Unicode *)
let unicode = unicode_of_ascii "\\<Rightarrow>";
(* Result: "⇒" *)

(* Convert Unicode to ASCII notation *)
let ascii = ascii_of_unicode "⇒";
(* Result: "\\<Rightarrow>" *)
```

## API Documentation

### Client Operations

- `create : ?timeout:float -> string -> string -> client`
  - Connect to REPL server
  - Parameters: address, theory qualifier, optional timeout

- `close : client -> unit`
  - Close client connection

- `eval : ?timeout:int -> ?cmd_timeout:int -> ?import_dir:string -> client -> string -> Msgpack.t`
  - Evaluate Isabelle source code

- `lex : client -> string -> Msgpack.t`
  - Split source into command sequence

- `file : ?line:int -> ?column:int -> ?timeout:int -> ?attrs:string list -> ?cache_position:bool -> ?use_cache:bool -> client -> string -> unit`
  - Evaluate an Isabelle file

### State Management

- `record_state : client -> string -> unit`
  - Record current evaluation state

- `rollback : client -> string -> Msgpack.t`
  - Rollback to recorded state

- `history : client -> Msgpack.t`
  - Get history of recorded states

- `clean_history : client -> unit`
  - Clear all recorded states

### Settings

- `set_trace : client -> bool -> unit`
  - Enable/disable output collection

- `set_thy_qualifier : client -> string -> unit`
  - Change theory qualifier

- `set_cmd_timeout : client -> int option -> unit`
  - Set command timeout

### Term and Fact Operations

- `sexpr_term : client -> string -> Msgpack.t`
  - Parse term to S-expression

- `fact : client -> string -> Msgpack.t`
  - Retrieve facts (lemmas, theorems)

- `sexpr_fact : client -> string -> Msgpack.t`
  - Retrieve facts as S-expressions

- `context : ?pp:string -> client -> Msgpack.t`
  - Get current proof context

### Automation

- `hammer : client -> int -> Msgpack.t`
  - Invoke Sledgehammer with timeout

### Symbol Operations

- `unicode_of_ascii : string -> string`
  - Convert ASCII notation to Unicode

- `ascii_of_unicode : string -> string`
  - Convert Unicode to ASCII notation

## Theory Qualifier

The `thy_qualifier` parameter is the session name used to resolve short theory names. When evaluating a theory file, you should set this to the session name of that file.

For example:
- For HOL theories: `"HOL"`
- For AFP theories: use the AFP project name, e.g., `"WebAssembly"`

To find the session name of a theory file:
```ocaml
let session = session_name_of client "/path/to/Theory.thy"
```

## License

This library is part of the Isa-REPL project and is licensed under LGPL-3.0-or-later.

## Credits

- Original Python implementation by Qiyuan Xu
- OCaml translation: [Your Name]

## Links

- [Isa-REPL GitHub](https://github.com/xqyww123/Isa-REPL)
- [Isabelle](https://isabelle.in.tum.de/)

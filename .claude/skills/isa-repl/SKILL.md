---
name: isa-repl
description: Locate and understand the Isa-REPL project providing REPL interface for Isabelle
---

# Isa-REPL Project

Isa-REPL provides a programmatic REPL (Read-Eval-Print-Loop) interface for Isabelle, enabling client programs to interact with Isabelle over sockets. Designed for machine learning applications and automated theorem proving.

## Project Location

**Path:** repository root (this project, i.e. `contrib/Isa-REPL/`).

Packaged as the pip project **`IsaREPL`** (see `pyproject.toml`, currently version 0.14.1, prebuilt wheel under `dist/`). Installable with `pip install IsaREPL`. Supports Isabelle2026 only (branch `main`).

## IMPORTANT: Theories are auto-loaded — the heap is only a speed cache

A common misconception is that only theories compiled into the running
session's heap can be used. **False.** Isa-REPL auto-loads any imported theory
not in the heap from its `.thy` source: `thy_loader` (`library/REPL.ML`) hands it
to Isabelle_RPC's `PIDE_Loader`, which loads it through the PIDE document of the
server's session, as Isabelle/jEdit does. The startup session (`HOL`,
`HOL-Analysis`, …) only decides what comes *precompiled/fast*, not what you may
import.

**Real precondition** (not "must be in the heap"): the `.thy` source must be
**locatable** — via the session's sources/import search path, the REPL's
`import_dir`, or relative to the target theory. If not, the loader's error names
the theory or the file it could not load.

Differences between heap theories and theories loaded from files:

- A loaded file is read **once per server process**; edits on disk are not seen
  until the server restarts.
- A loaded file is named by its folder: `S.<file name>` if a known session `S`
  owns the folder, else `Draft.<file name>`. A `Draft` theory is requested by its
  path, not by that name; inside a `Draft` file write `imports "HOL.List"`, not
  `imports List`.
- Two different files with one long name: the second is refused.
- Inside the REPL process, `Build.get_theory` / `Build.lookup_theory` see only
  heap theories; use `PIDE_Loader.get_theory` / `PIDE_Loader.lookup_theory`
  (heap theories and loaded theories).

## Directory Structure

### `IsaREPL/` - Python Client Library
Python client package for communicating with the Isabelle REPL server:
- `IsaREPL.py` - Main Python client (MessagePack-based communication)
- `__init__.py` - Package entry
- Socket-based communication protocol, session management and state tracking

### `clients/` - Additional Clients
- `clients/ocaml/` - An OCaml client (dune project `isa_repl`, with `lib/`, `examples/`, opam packaging, and its own README/notes)

### `library/` - ML Server Implementation
Core Isabelle/ML server-side components. These are loaded by `Isa_REPL.thy` in this order:
`premise_selection.ML → REPL.ML → REPL_serializer.ML → REPL_aux.ML → Server.ML`.
- `REPL.ML` - REPL signature and main implementation (also implements the Sledgehammer solving path)
- `Server.ML` - Socket server implementation
- `REPL_serializer.ML` - Serialization of Isabelle objects (terms, theorems, states)
- `REPL_aux.ML` - Auxiliary/utility functions used by the REPL
- `premise_selection.ML` - Premise selection support for proof search
- `sledgehammer.ML` - Sledgehammer solver signature/helpers. NOTE: this file is present but is **not** loaded by `Isa_REPL.thy`; the live Sledgehammer integration lives in `REPL.ML`/`premise_selection.ML`.

(There is also a top-level `REPL_aux.ML` alongside `library/REPL_aux.ML`.)

### `examples/` - Usage Examples
Example Python scripts demonstrating various REPL features:
- **`example_eval.py`** - Basic REPL usage (evaluating commands)
- **`example_context.py`** - Retrieve proof context (facts, assumptions, fixed variables, goals)
- **`example_parse.py`** - Parse terms and retrieve lemmas
- **`example_lex.py`** - Split scripts into command sequences (lexical analysis)
- **`example_plugin.py`** - Install/uninstall plugins to access Isabelle internals
- **`example_rollback.py`** - State rollback and history management
- **`example_sledgehammer.py`** - Use Sledgehammer for automated proving
- **`example_watcher.py`** - Monitor client status (alive/errors)
- **`example_pretty_unicode.py`** - Unicode/ASCII symbol conversion
- **`eval_file.py`** - Evaluate entire theory files
- **`test_file.py`** - Evaluate theory files with error checking
- **`lex_file.py`** - Lexical analysis of files
- **`parse_thy_header.py`** - Parse theory headers (imports, keywords)
- **`path_of.py`** - Get file path of a theory
- **`session_of.py`** - Get session name of a file
- **`premise_selection.py`** - Premise selection for proof search
- **`test_config.py`**, **`test_eval.py`**, **`test_load_theory.py`** - Additional test/example scripts
- **`run_all_parallel.sh`** - Run the examples in parallel

### `tools/` - Utilities
- `isabelle2unicode.py`, `unicode2isabelle.py` - Unicode/ASCII conversion tools for Isabelle symbols

### `contrib/mlmsgpack/` - Serialization
MessagePack library for ML (binary serialization format)

### `doc/` - Documentation
- `doc/Readme.md`

## Key Files

### Entry Point
- **`Isa_REPL.thy`** - Main theory file loading all ML components (see load order above)
- **`ROOT`** - Isabelle session definition
- **`src/scala/repl_tool.scala`** - The `isabelle REPL` tool that starts the server (prebuilt in `lib/isa_repl.jar`)
- **`repl_server_watch_dog.sh`** - Watchdog wrapper that restarts the server
- **`README.md`** - Installation and usage overview

### Python Interface
- **`IsaREPL/IsaREPL.py`** - Client API for sending commands and receiving results
- **`pyproject.toml`** - Packaging metadata for the `IsaREPL` pip project

### ML Core
- **`library/REPL.ML`** - Core REPL logic, command execution, state management

## Usage Pattern

1. **Install client (optional):** `pip install IsaREPL`
2. **Register component & start server:** e.g. `isabelle components -u .`, then
   `isabelle REPL -l HOL -o threads=16 127.0.0.1:6666 <absolute output dir>`
   (options first; `isabelle REPL -?` lists them. You must explicitly set the thread
   count; Isabelle defaults to 8 cores.)
3. **Connect from a client:** Use `IsaREPL.Client` (Python) or the OCaml client under `clients/ocaml/`.

## Common Use Cases

For concrete usage examples, see the scripts in `examples/`:
- **Basic REPL usage:** Start with `example_eval.py`
- **Data collection for ML:** Use `example_context.py` and `example_plugin.py` to extract proof state and internal data
- **Automated theorem proving:** See `example_sledgehammer.py` for Sledgehammer integration
- **Theory file evaluation:** Use `eval_file.py` or `test_file.py` to process complete theory files
- **State management:** Check `example_rollback.py` for state rollback and checkpointing
- **Parsing and analysis:** Use `example_parse.py`, `example_lex.py`, and `parse_thy_header.py`

## Finding Your Way

### To understand the protocol:
- Read `IsaREPL/IsaREPL.py` (Python client)
- Check `library/REPL.ML` and `library/Server.ML` (ML server)

### To extend functionality:
- Add ML functions in `library/`
- Create plugins for custom data extraction
- Modify `Isa_REPL.thy` to load new ML files (remember to add them to the load list)

### To debug:
- Check the console output of `isabelle REPL` or `repl_server_watch_dog.sh`. To see prover
  messages, start the server with `-L FILE`: FILE always gets the messages of theories loaded
  from files; the server's own messages (those of `eval`, `file` and plugins, including
  `writeln` traces you add to the ML they run) are muted by default and reach FILE only if the
  server is also started with `-V`.
- Enable debug mode in the client
- Trace ML execution in `library/REPL.ML`

# Changelog

## 0.13.0 (2024-12-11)

### Initial Release

First public release of the OCaml client for Isabelle REPL.

**Features**:
- Complete OCaml translation of Python IsaREPL client
- Full REPL functionality (eval, lex, state management)
- Plugin system support
- Unicode/ASCII symbol conversion
- MessagePack-based communication
- Comprehensive examples and documentation

**Dependencies**:
- OCaml >= 4.14
- msgpck >= 1.7
- re
- unix, str (standard library)

**Compatibility**:
- Compatible with Isabelle REPL server version 0.13.0
- Tested with Isabelle 2024

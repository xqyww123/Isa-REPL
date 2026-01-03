#!/bin/bash
# Test script for OCaml examples

SERVER="127.0.0.1:6666"

echo "=========================================="
echo "Testing OCaml IsaREPL Client Examples"
echo "Server: $SERVER"
echo "=========================================="
echo

# Test 1: Pretty Unicode (no server needed)
echo "Test 1: Pretty Unicode conversion"
echo "------------------------------------------"
opam exec -- dune exec examples/example_pretty_unicode.exe
echo
echo

# Test 2: Basic eval
echo "Test 2: Basic evaluation"
echo "------------------------------------------"
timeout 60 opam exec -- dune exec examples/example_eval.exe $SERVER || echo "Test failed or timeout"
echo
echo

# Test 3: Lex
echo "Test 3: Lexing"
echo "------------------------------------------"
timeout 30 opam exec -- dune exec examples/example_lex.exe $SERVER || echo "Test failed or timeout"
echo
echo

# Test 4: Rollback
echo "Test 4: State rollback"
echo "------------------------------------------"
timeout 30 opam exec -- dune exec examples/example_rollback.exe $SERVER || echo "Test failed or timeout"
echo
echo

# Test 5: Context
echo "Test 5: Proof context"
echo "------------------------------------------"
timeout 30 opam exec -- dune exec examples/example_context.exe $SERVER || echo "Test failed or timeout"
echo
echo

# Test 6: Plugin
echo "Test 6: Plugin system"
echo "------------------------------------------"
timeout 30 opam exec -- dune exec examples/example_plugin.exe $SERVER || echo "Test failed or timeout"
echo
echo

echo "=========================================="
echo "All tests completed!"
echo "=========================================="

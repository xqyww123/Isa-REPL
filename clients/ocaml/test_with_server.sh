#!/bin/bash
set -e

SERVER_ADDR="127.0.0.1:6698"   # a free port, NOT the production 6666
SERVER_PORT="6698"
SERVER_LOG="/tmp/repl_server.log"

echo "=========================================="
echo "OCaml Client Test with Server"
echo "=========================================="
echo

# Start server in background
echo "Starting Isabelle REPL server..."
cd /home/qiyuan/Current/MLML
source ./envir.sh
isabelle REPL -l HOL -o threads=14 -o document=false $SERVER_ADDR /tmp/repl_outputs > $SERVER_LOG 2>&1 &
echo "Server launcher started; log: $SERVER_LOG"

# Function to cleanup: the launcher's PID is a bash layer, not the JVM, so kill
# by port instead (Client.kill would need the 0.15.0 client on both ends).
cleanup() {
    echo
    echo "Cleaning up (killing whatever listens on $SERVER_PORT)..."
    fuser -n tcp -k "$SERVER_PORT" 2>/dev/null || true
    sleep 2
    echo "Done."
}
trap cleanup EXIT

# Wait for the server to be ready: poll the port (the ready line is also in $SERVER_LOG)
echo "Waiting for the server to listen on $SERVER_PORT (heap load can take ~90s)..."
for i in $(seq 1 180); do
    if ss -ltn 2>/dev/null | grep -q ":$SERVER_PORT "; then echo "Server is listening."; break; fi
    if grep -q 'server ready at' "$SERVER_LOG" 2>/dev/null; then echo "Server ready."; break; fi
    sleep 1
done
echo

# Go back to ocaml client directory
cd /home/qiyuan/Current/MLML/contrib/Isa-REPL/clients/ocaml

# Test 1: Connection test
echo "=========================================="
echo "Test 1: Connection Test"
echo "=========================================="
opam exec -- dune exec examples/test_connection.exe $SERVER_ADDR
echo

# Test 2: Simple test
echo "=========================================="
echo "Test 2: Simple Evaluation"
echo "=========================================="
timeout 60 opam exec -- dune exec examples/simple_test.exe $SERVER_ADDR || echo "Test failed or timeout"
echo

echo "=========================================="
echo "Server log tail:"
echo "=========================================="
tail -20 $SERVER_LOG

echo
echo "Tests completed!"

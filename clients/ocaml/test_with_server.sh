#!/bin/bash
set -e

SERVER_ADDR="127.0.0.1:6666"
SERVER_LOG="/tmp/repl_server.log"

echo "=========================================="
echo "OCaml Client Test with Server"
echo "=========================================="
echo

# Start server in background
echo "Starting Isabelle REPL server..."
cd /home/qiyuan/Current/MLML
source ./envir.sh
./contrib/Isa-REPL/repl_server.sh $SERVER_ADDR ITP4SMT /tmp/repl_outputs -o threads=14 -o document=false > $SERVER_LOG 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
echo "Server log: $SERVER_LOG"

# Function to cleanup
cleanup() {
    echo
    echo "Cleaning up..."
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        sleep 2
        kill -9 $SERVER_PID 2>/dev/null || true
    fi
    echo "Done."
}
trap cleanup EXIT

# Wait for server to be ready
echo "Waiting 30 seconds for server to initialize..."
for i in {1..30}; do
    echo -n "."
    sleep 1
done
echo
echo "Server should be ready now."
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

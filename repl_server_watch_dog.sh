#!/bin/bash
# Watchdog (plan 二 §6.2, T19/T20): keep an Isa-REPL server online.  Its command
# line is exactly `isabelle REPL`'s -- options FIRST, then ADDR OUTPUT_DIR:
#
#   repl_server_watch_dog.sh [OPTIONS] ADDR OUTPUT_DIR
#
# There is no client-initiated clean shutdown (the server is only killed by the
# SIGKILL of Client.kill()), so the loop reboots unconditionally; to stop the
# service, kill this watchdog first, then the server.

echo 0 > /proc/$$/oom_score_adj 2> /dev/null
echo -1000 > /proc/$$/oom_score_adj 2> /dev/null

# Usage guard (M5): ADDR (host:port) must be the second-to-last argument, so
# options must come FIRST.  Without this guard, the old habit of trailing
# options (`... ADDR DIR -o threads=N`) makes `isabelle REPL` fail with four
# positionals (rc 1) and this loop -- which no longer has a success exit --
# would spin forever without ever starting a server.
if [ $# -lt 2 ]; then
  echo "Usage: repl_server_watch_dog.sh [OPTIONS] ADDR OUTPUT_DIR   (options FIRST, like isabelle REPL)" >&2
  exit 2
fi
addr="${@: -2:1}"
if [[ "$addr" == -* || "$addr" != *:* ]]; then
  echo "Usage: repl_server_watch_dog.sh [OPTIONS] ADDR OUTPUT_DIR" >&2
  echo "  ADDR (host:port) must be the second-to-last argument; put every option FIRST." >&2
  exit 2
fi
port="${addr##*:}"

if [ -z "$(isabelle getenv -b ISA_REPL_HOME)" ]; then
  BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  echo "ERROR: the Isa-REPL Isabelle component is not registered on this machine," >&2
  echo "       so \`isabelle REPL\` is not a known tool.  Register it once with:" >&2
  echo "           isabelle components -u \"$BASE_DIR\"" >&2
  exit 2
fi

while true; do
  isabelle REPL "$@"
  echo "The server terminated with code $?.  Killing port $port and rebooting..." >&2
  fuser -n tcp -k "$port" 2> /dev/null || true
  sleep 2
done

#!/bin/bash
# Thin wrapper (plan 二 §6.2): translate the old positional call
#   repl_server.sh <ADDR> <BASE_SESSION> <OUTPUT_DIR> [-d DIR]... [-o OPT]...
# into the `isabelle REPL` tool, which replaces it:
#   isabelle REPL -l BASE_SESSION [-d DIR]... [-o OPT]... ADDR OUTPUT_DIR
# Kept for one version, then deleted.  New callers should use `isabelle REPL`
# directly.  Only -d and -o are forwarded; the old "-l SESSION" (add a session
# to the generated ROOT) is dropped -- every session's theories are importable
# now -- and any other flag is refused (the old promise to pass arbitrary flags
# to `isabelle build` would silently change their meaning, e.g. -v).

echo "note: repl_server.sh is now a thin wrapper for \`isabelle REPL\`; new callers should use \`isabelle REPL [OPTIONS] ADDR OUTPUT_DIR\` directly." >&2

if [ -z "$(isabelle getenv -b ISA_REPL_HOME)" ]; then
  BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  echo "ERROR: the Isa-REPL Isabelle component is not registered on this machine," >&2
  echo "       so \`isabelle REPL\` is not a known tool.  Register it once with:" >&2
  echo "           isabelle components -u \"$BASE_DIR\"" >&2
  exit 2
fi

if [ $# -lt 3 ]; then
  cat >&2 <<EOF
Usage: repl_server.sh <ADDR> <BASE_SESSION> <OUTPUT_DIR> [-d DIR]... [-o OPT]...

  A thin wrapper for:
      isabelle REPL -l <BASE_SESSION> [-d DIR]... [-o OPT]... <ADDR> <OUTPUT_DIR>
EOF
  exit 1
fi

ADDR="$1"; BASE_SESSION="$2"; OUTPUT_DIR="$3"; shift 3

opts=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      [ -n "${2:-}" ] || { echo "ERROR: -o needs an argument" >&2; exit 1; }
      opts+=(-o "$2"); shift 2 ;;
    -d)
      [ -n "${2:-}" ] || { echo "ERROR: -d needs an argument" >&2; exit 1; }
      opts+=(-d "$2"); shift 2 ;;
    -l)
      echo "note: '-l $2' is no longer needed -- under \`isabelle REPL\` every session's" >&2
      echo "      theories are importable, so the old 'add to the generated ROOT' use is gone; dropping it." >&2
      shift 2 ;;
    *)
      echo "ERROR: repl_server.sh no longer forwards arbitrary flags to \`isabelle build\`." >&2
      echo "       Unknown flag: $1.  Use \`isabelle REPL [OPTIONS] ADDR OUTPUT_DIR\` instead." >&2
      exit 1 ;;
  esac
done

exec isabelle REPL -l "$BASE_SESSION" "${opts[@]}" "$ADDR" "$OUTPUT_DIR"

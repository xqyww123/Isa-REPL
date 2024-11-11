#!/bin/bash

if [[ $# -lt 3 ]] ; then
  cat <<EOF
This is Isabelle REPL server.

repl_server <ADDR> <BASE_SESSION> <OUTPUT_DIR> [OPTIONS]

Mandatory Arguments

ADDR          :  The address on which this sever listens, e.g., "127.0.0.1:6666"
BASE_SESSION  :  An Isabelle session. Only theories within BASE_SESSION and other sessions
                 indicated by '-l' can be loaded by this shell.
                 Set this to 'HOL' if you have no idea and we strongly refer you to Isabelle's
                 system reference, chapter 2 <Isabelle sessions and build management>.
OUTPUT_DIR    :  The directory that stores all files generated when running the Isabelle
                 theories evaluated by this shell.
                 The path must be given in POSIX format, in which only forward-slash like
                 "a/b/c" is valid but backslash like "a\\b\\c" is invalid.

Optional Options

 -l SESSION_NAME  :  Additional sessions to be loaded by this shell.
                     The difference between "-l" and "BASE_SESSION" is that, this shell
                     could reuse the built cache of the BASE_SESSION but for sessions
                     indicated by "-l", they must be re-built every single time running
                     this REPL server.

ANY OTHER OPTIONS    will pass to <isabelle build> command. So you could use any option
                     accepted by <isabelle build>, e.g., -o thread=6

Example

repl_server 127.0.0.1:6666 HOL /tmp/repl_outputs
EOF
    exit 1
fi

ADDR="$1"
BASE_SESSION="$2"
MASTER_DIR="$3"
shift 3


# Parse -l arguments
l_values=()
other_options=()

while [[ $# -gt 0 ]]; do
    key="$1"
    if [[ "$key" == "-l" ]]; then
        if [[ -n "$2" && "$2" != -* ]]; then
            l_values+=("$2")
            shift 2
        else
            echo "ERROR：-l option needs an argument"
            exit 1
        fi
    else
        other_options+=("$1")
        shift
    fi
done


formatted_l_values=""

for val in "${l_values[@]}"; do
    escaped_val="${val//\"/\\\"}"
    formatted_l_values+="\"$escaped_val\" "
done

options=""

for val in "${other_options[@]}"; do
    escaped_val="${val//\"/\\\"}"
    options+="$escaped_val "
done

echo $options

echo "Hi, this is Isabelle REPL Server."
echo "When you see \"Running REPL$$ ...\", it means I am successfully lanched and listening on $ADDR."

DIR="$(mktemp -d)"

cat <<EOF > $DIR/REPL$$.thy
theory REPL$$
imports "Isa_REPL.Isa_REPL"
begin
ML \\<open>Isabelle_Thread.join (REPL_Server.startup (Path.explode "$(printf '%b' $MASTER_DIR)") NONE "$(printf '%b' $ADDR)");
  error "IGNORE THIS ERROR"\\<close>
end
EOF

cat <<EOF > $DIR/ROOT
session REPL$$ = "$(printf '%b' $BASE_SESSION)"
 + sessions Isa_REPL $formatted_l_values
   theories REPL$$
EOF

echo isabelle build -D $DIR $options REPL$$
isabelle build -D $DIR $options REPL$$

#rm $DIR -r

#isabelle process -l $2 -f $base/contrib/mlmsgpack/mlmsgpack-aux.sml -f $base/contrib/mlmsgpack/realprinter-packreal.sml -f $base/contrib/mlmsgpack/mlmsgpack.sml -f $base/library/REPL.ML -f $base/library/REPL_serializer.ML -f $base/library/Server.ML -e "REPL_Server.startup ${(qqq)3} NONE ${(qqq)1}"


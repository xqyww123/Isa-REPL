#!/bin/bash

if [[ $# != 2 ]] ; then
    echo 'ERROR: Bad arguments'
    echo 'USAGE: repl_server <ADDR> <SESSION>'
    echo 'Argument ADDR: the address on which this sever listens, e.g., "127.0.0.1:6666"'
    echo "Argument SESSION: an Isabelle session. Only theories within this session can be loaded by this shell. set this to 'HOL' if you have no idea and we strongly refer you to Isabelle's system reference, chapter 2 <Isabelle sessions and build management>."
    echo 'Example: repl_server 127.0.0.1:6666 HOL'
    exit 1
fi

base=$(dirname $0)

isabelle process -l $2 -f $base/contrib/mlmsgpack/mlmsgpack-aux.sml -f $base/contrib/mlmsgpack/realprinter-packreal.sml -f $base/contrib/mlmsgpack/mlmsgpack.sml -f $base/library/REPL.ML -f $base/library/REPL_serializer.ML -f $base/library/Server.ML -e "REPL_Server.startup NONE \"$1\""


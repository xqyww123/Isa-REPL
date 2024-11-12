#!/bin/bash

if [[ $# -lt 1 ]] ; then
  cat <<EOF
./run_all_parallel.sh <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is mandatory.
EOF
  exit 1
fi

SCRIPT=$(readlink -f $0)
BASE=$(dirname $SCRIPT)

$BASE/example_eval.py $1 &
$BASE/example_lex.py $1 &
$BASE/example_plugin.py $1 &
$BASE/example_sledgehammer.py $1 &
$BASE/eval_file.py $1 $(isabelle getenv -b ISABELLE_HOME)/src/HOL/List.thy



#!/bin/env python
USAGE = """
USAGE: example_slegehammer.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.

Isabelle command "sledgehammer" is an asynchronous command, which will output something
even when the main process of the command is returned.
The workflow of REPL basically cannot capture the message printed after its return.
Therefore, we recommend users to use [Auto_Sledgehammer](https://github.com/xqyww123/auto_sledgehammer)
also written by me. It is smart enough to automatically select the first usable
tactic returned by Sledgehammer, and seamlessly intergrate it into Isabelle's tactic
language. This example demonstartes how to use this handy tool.

To run this example, you must have installed [Auto_Sledgehammer](https://github.com/xqyww123/auto_sledgehammer).

Note: To fully wield the concurrency power of Isabelle, please pass options "-j<N> -o threads=<N>" to "./repl_server", replacing <N> to the number of CPU cores you want to use,
e.g, "./repl_server.sh 127.0.0.1:6666 Main /tmp/repl_outputs -j 32 -o threads=32"

This <N> only affects the cores for Sledgehammer. The evaluation of each theory file still uses its own thread, and the number of such threads is unlimited.

"""

from IsaREPL import Client
import json
import sys

if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
c = Client(addr)

def echo_eval (src):
    print('>>> '.join(src.splitlines(True)))
    ret = c.silly_eval(src)
    print(json.dumps(ret, indent=2))
    return ret

echo_eval("""
theory HHH
  imports Main "Auto_Sledgehammer.Auto_Sledgehammer"
begin
definition "ONE = (1::nat)"
lemma "ONE + ONE = 2"
    by auto_sledgehammer (*HERE, we are calling Sledgehammer!*)
end
""")


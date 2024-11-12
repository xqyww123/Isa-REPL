#!/bin/env python
USAGE = """
USAGE: example_rollback.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.

This script demonstrates the basic usage of state rollback.
"""

from IsaREPL import Client
import json
import sys


if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]

c = Client(addr)

def pp(x):
    print(json.dumps(x, indent=2))
    return x

def echo_eval (src):
    print('>>> '.join(src.splitlines(True)))
    ret = c.silly_eval(src)
    return pp(ret)

echo_eval ("""
theory HHH
imports Main
begin
lemma "\<exists>x::nat. x + 1 = 2"
""")

c.record_state("S0")

echo_eval("""
    apply (rule exI[where x=666])
""")

c.record_state("S1")
print("Recorded histories:")
pp(c.silly_history())
print("rollback to state S0")
pp(c.silly_rollback ("S0"))

echo_eval("""
    by (rule exI[where x=1], auto)
end
""")

c.close()


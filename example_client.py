#!/bin/env python
USAGE = """
example_client.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.
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


echo_eval ("""theory AA
imports Main
begin
lemma hh: True
term "2::nat"
"""
)

echo_eval ("""
""")

echo_eval ("""
    apply simp
    done
term "1::nat"
thm conjI
thm hh
""")

echo_eval ("""
definition "ONE = (1::nat)"
definition "TWO = (2::nat)"
""")

echo_eval ("""
lemma "ONE + ONE = TWO"
    unfolding ONE_def TWO_def
    by auto
""")



c.close()


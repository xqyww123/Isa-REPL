#!/bin/env python
USAGE = """
USAGE: example_context.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.

This script demonstrates how to retriev the proof context that includes useful contextual data
    including local facts, assumptions, bindings (made by `let` command),
    fixed term variables (and their types), fixed type variables (and their sorts), and goals.
"""

from IsaREPL import Client
import json
import sys


if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]

c = Client(addr, 'HOL')

def echo_eval (src):
    print('>>> '.join(src.splitlines(True)))
    ret = c.silly_eval(src)
    print(json.dumps(ret, indent=2))
    return ret

def pp (x):
    print(json.dumps(x, indent=2))
    return x

echo_eval ("""
theory HHH
imports Main
begin

lemma "Assumption1 (x::nat) ==> Assumption2 (y::int) ==> Qiyuan Great \<and> Worship Qiyuan"
subgoal premises prems proof
  have lem: "1 + 1 = (2::nat)" by auto
""")

pp(c.silly_context(False))
c.close ()


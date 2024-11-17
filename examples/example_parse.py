#!/bin/env python
USAGE = """
USAGE: example_parse.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.

This script demonstrates how to parse terms and retrieve lemmas.
"""

from IsaREPL import Client
import json
import sys


if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]

c = Client(addr)

def pp (x):
    print(json.dumps(x, indent=2))
    return x

# You must at least evaluate a theory header before parsing any term or
# retrieving any lemmas.
# This header is necessary to indicate the theory under which the terms
# will be parsed and the lemmas will be retrived
c.eval ("""
theory THY
imports Main
begin
""")
print(1)

pp (c.fact("conj_assoc[symmetric] HOL.simp_thms"))
pp (c.sexpr_term("(2::nat)"))

c.eval ("""
lemma t1: "(1::nat) + 1 = 2" by auto
thm t1
""")

pp (c.fact("t1[symmetric]"))

c.close ()


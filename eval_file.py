#!/bin/env python

USAGE = """
eval_file.py <ADDRESS OF SERVER> <TARGET ISABELLE THEORY FILE TO EVALUATE>
"""

from IsaREPL import Client
import sys

if len(sys.argv) != 3:
    print(USAGE)
    exit(1)

addr   = sys.argv[1]
target = sys.argv[2]

c = Client(addr)
c.set_trace (False)

def is_empty(obj):
    return obj == [] or obj == ""

with open(target, "r") as file:
    content = file.read()
    print("Lex:")
    print (c.lex(content))
    ret = c.eval(content)
    if not is_empty(ret[1]) and not ret[1] is None:
        print(ret[1])
        exit(1)

print("success")
exit(0)


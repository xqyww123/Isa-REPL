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

def is_empty(obj):
    return obj == [] or obj == ""

with open(target, "r") as file:
    content = file.read()
    ret = c.eval(content)
    for out in ret[0]:
        print(out)
        if not is_empty(out[6]):
            print(out[6])
            exit(1)
    if not is_empty(ret[1]):
        print(ret[1])
        exit(1)

print("success")
exit(0)


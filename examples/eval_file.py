#!/bin/env python

USAGE = """
eval_file.py <ADDRESS OF SERVER> <TARGET ISABELLE THEORY FILE TO EVALUATE>

Evaluate an entire theory file.

Example

./examples/eval_file.py 127.0.0.1:6666 $(isabelle getenv -b ISABELLE_HOME)/src/HOL/List.thy:8407:2

"""

from IsaREPL import Client
import sys

if len(sys.argv) != 3:
    print(USAGE)
    exit(1)

addr   = sys.argv[1]
target, line, column = sys.argv[2].split(':')
line=int(line)
column=int(column)

c = Client(addr, 'HOL')
c.set_register_thy (False) # preventing the REPL to reigster he evaluated theories
                # to the Isabelle system. This suppresses the `duplicate exports`
                # errors.

# c.set_trace (False) # You could uncomment this line to disable the tracing
                      # and to speed up the evaluation.
#                     # Consequently, the later `ret` will be None

def is_empty(obj):
    return obj == [] or obj == ""

ret = c.file (target, line=line, column=column, cache_position=True, use_cache=True)
print ('errors encountered:')
print(ret)

print("success")
exit(0)


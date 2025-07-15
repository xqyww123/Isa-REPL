#!/usr/bin/env python3

from IsaREPL import Client, REPLFail
import sys

USAGE = """
Usage: python premise_selection.py <addr> <file>:<line> <number> <methods> <printer>
"""

if len(sys.argv) != 6:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
target, line = sys.argv[2].split(':')
number = int(sys.argv[3])
methods = sys.argv[4].split(',')
printer = sys.argv[5]

c = Client(addr, 'HOL')
c.set_register_thy (False) # preventing the REPL to reigster he evaluated theories
                # to the Isabelle system. This suppresses the `duplicate exports`
                # errors.
try:
    c.file (target, line=int(line), cache_position=True, use_cache=True)
except REPLFail as e:
    print ('errors encountered:')
    print(e)
    exit(1)

res = c.premise_selection(number, methods, {}, printer)
print ('premise selection results:')
for k, v in res.items():
    print(f'{k}: {v}')


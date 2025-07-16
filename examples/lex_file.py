#!/usr/bin/env python3
USAGE = """
USAGE: lex_file.py <ADDRESS OF SERVER> <FILE>
"""

from IsaREPL import Client
import json
import sys
import os

if len(sys.argv) != 3:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
file = sys.argv[2]

with Client(addr, 'HOL') as c:
    lex = c.lex_file(file)
    for pos, src in lex:
        print(f"{pos.line}:{pos.column}: {src}")
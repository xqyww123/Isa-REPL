#!/bin/env python

import os
import sys
from IsaREPL import Client

USAGE = """
parse_thy_header.py <ADDRESS OF SERVER> <TARGET ISABELLE THEORY FILE TO PARSE>

Prints the names of the theories to import and their file paths;
also prints the keyword declarations.

./examples/parse_thy_header.py 127.0.0.1:6666 $(isabelle getenv -b ISABELLE_HOME)/src/HOL/List.thy

"""

if len(sys.argv) != 3:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
target = sys.argv[2]

c = Client(addr, 'HOL')
s = c.session_name_of(target)
c.set_thy_qualifier(s)
with open(target, 'r') as f:
    header_src = f.read()
thy_name, imports, keywords = c.parse_thy_header(header_src)

dir = os.path.dirname(target)

print(f"session: {s}")
print(f"thy_name: {thy_name}")
print(f"imports:")
for i in imports:
    print(f"  {i}: {c.path_of_theory(i, dir)}")
print(f"keywords: {keywords}")

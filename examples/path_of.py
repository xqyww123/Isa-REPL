#!/usr/bin/env python3
USAGE = """
path_of.py <ADDRESS OF SERVER> <THEORY NAME> <MASTER DIRECTORY>

Get the path of a theory.

Example

./examples/path_of.py 127.0.0.1:6666 HOL.List $(isabelle getenv -b ISABELLE_HOME)/src

"""

from IsaREPL import Client
import sys

if len(sys.argv) != 4:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
theory_name = sys.argv[2]
master_directory = sys.argv[3]

c = Client(addr, 'HOL')
print(c.path_of_theory(theory_name, master_directory))

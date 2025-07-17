#!/usr/bin/env python3

USAGE = """
session_of.py <address> <file>
"""

import sys
from IsaREPL import Client

if len(sys.argv) != 3:
    print(USAGE)
    sys.exit(1)

address, file = sys.argv[1], sys.argv[2]
with Client(address, 'HOL') as c:
    print(c.session_name_of(file))
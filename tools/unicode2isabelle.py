#!/usr/bin/env python3
import IsaREPL

try:
    while True:
        line = input()
        print(IsaREPL.Client.ascii_of_unicode(line))
except EOFError:
    pass

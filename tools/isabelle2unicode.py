#!/usr/bin/env python3
import IsaREPL

try:
    while True:
        line = input()
        print(IsaREPL.Client.unicode_of_ascii(line))
except EOFError:
    pass

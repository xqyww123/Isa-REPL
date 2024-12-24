#!/bin/env python
USAGE = """
USAGE: example_lex.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.
"""

from IsaREPL import Client
import json
import sys

if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
c = Client(addr, 'HOL')

print("""
This example demonstrates how to split a script into a
sequence of code pieces each of which is led by and contains
exactly one command.
""")

SRC = """
(*Any comments and blank spaces before the first command will be discarded..*)
text "Something funny"
(*this comment will be appended to the previous `text` command*)
theory KKK
  imports HHH
begin

lemma "ONE + ONE = 2"
    (*this comment will be appended to the previous `lemma` command*)
    unfolding ONE_def
    by auto

context begin
private lemma True by auto
end

end
"""
print("Source:")
print(SRC)
print("LEX result:")
print(c.lex(SRC))

c.close()


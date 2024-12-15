#!/bin/env python

USAGE = """
test_file.py <ADDRESS OF SERVER> <TARGET ISABELLE THEORY FILE TO EVALUATE>

Evaluate an entire theory file.

Example

./examples/eval_file.py 127.0.0.1:6666 $(isabelle getenv -b ISABELLE_HOME)/src/HOL/List.thy

"""

from IsaREPL import Client
import sys

if len(sys.argv) != 3:
    print(USAGE)
    exit(1)

addr   = sys.argv[1]
target = sys.argv[2]

c = Client(addr, 'HOL')

session = c.session_name_of (target)
if session:
    print ("The session is: " + session)
    c.set_thy_qualifier(session)
else:
    print ("Fail to infer the session of the target file. The evaluation can fail.")

def is_empty(obj):
    return obj == [] or obj == ""

with open(target, "r") as file:
    content = file.read()
    ret = c.eval(content)
    if ret[0]:
        for a in ret[0]:
            if a[7]:
                for x in a[7]:
                    print(x)
                exit(1)
    if not is_empty(ret[1]) and not ret[1] is None:
        print(ret[1])
        exit(1)

print("success")
exit(0)


#!/bin/env python
USAGE = """
USAGE: example_eval.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.

This script demonstrates the basic usage of REPL.
"""

from IsaREPL import Client
import json
import sys


if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]

c = Client(addr, 'HOL')

def echo_eval (src):
    print('>>> '.join(src.splitlines(True)))
    ret = c.silly_eval(src)
    print(json.dumps(ret, indent=2))
    return ret

echo_eval ("""
section \<open>The datatype of finite lists\<close>

theory MyList
imports Sledgehammer Lifting_Set
begin
""")

echo_eval("""
datatype (set: 'a) list =
    Nil  ("[]")
  | Cons (hd: 'a) (tl: "'a list")  (infixr "#" 65)
for
  map: map
  rel: list_all2
  pred: list_all
where
  "tl [] = []"

context begin
lemma
  "(1::int) + 2 = 3"
  by smt
end

notepad begin
end

definition "ONE = (1::nat)"
end

theory HHH
  imports MyList
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end

theory GGG
  imports HHH
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end

theory KKK
  imports HHH
begin
lemma "ONE + ONE = 2"
    unfolding ONE_def
    by auto
end
""")


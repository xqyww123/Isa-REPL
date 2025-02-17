#!/bin/env python
USAGE = """
USAGE: example_plugin.py <ADDRESS OF SERVER>

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

def echo_eval (src):
    print('>>> '.join(src.splitlines(True)))
    ret = c.silly_eval(src)
    print(json.dumps(ret, indent=2))
    return ret

print("""
This example demonstrates how to install and uninstall plugins.
A plugin allows clients to access any internal representation of Isabelle.
Read the docstring of `Client.plugin` for more details.
""")

# This plugin collects all variables in a proof state.
c.plugin ("HOL.Main", "VARS", """
let open MessagePackBinIO.Pack
    fun packType ctxt = packString o REPL.trim_makrup o Syntax.string_of_typ ctxt
    fun collect_vars s =
        let val ctxt = Toplevel.context_of s
            val goal = Toplevel.proof_of s
                    |> Proof.goal
                    |> #goal
            val vars = Term.add_frees (Thm.prop_of goal) []
         in packPairList (packString, packType ctxt) vars
        end
 in fn {state=s,...} => (
        (if Toplevel.is_proof s then SOME (collect_vars s) else NONE),
        NONE) (*this plugin doesn't alter teh evaluation state*)
end
""")

echo_eval("""
theory TMP
    imports Main
begin
lemma "(a::nat) + b = b + a"
    by auto
end
""")
# You will find something printed like this in the output for the `lemma` command
# "plugin_output": {
#       "VARS": {
#         "b": "nat",
#         "a": "nat"
#       }
#     }

c.close()



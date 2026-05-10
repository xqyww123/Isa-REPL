#!/bin/env python3
"""Test Client.add_lib() auto-import semantics."""

import asyncio
import sys
sys.path.insert(0, '.')
from IsaREPL import Client

async def main():
    addr = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1:6666'

    # Test A: add_lib with MathBench_Prover, check ancestors
    print("=== Test A: add_lib, then list ancestors ===")
    async with Client(addr, 'HOL') as c:
        await c.set_trace(True)
        await c.add_lib(['MathBench_Prover.MathBench_Prover', 'Minilang_Agent.Minilang_Agent'])
        try:
            ret = await c.eval(
                'theory Test imports Main begin\n'
                'ML \\<open>\n'
                'val ancestors = Context.ancestors_of @{theory}\n'
                '  |> map Context.theory_long_name;\n'
                'val has_mathbench = exists (fn n => String.isSubstring "MathBench" n) ancestors;\n'
                'val has_minilang = exists (fn n => String.isSubstring "Minilang" n) ancestors;\n'
                'val _ = writeln ("has_mathbench = " ^ Bool.toString has_mathbench);\n'
                'val _ = writeln ("has_minilang = " ^ Bool.toString has_minilang);\n'
                '\\<close>\n'
                'end'
            )
            for r in ret:
                if r.output:
                    print(f"  {r.command[:40]}... output: {r.output}")
                if r.errors:
                    print(f"  {r.command[:40]}... errors: {r.errors}")
            print("OK")
        except Exception as e:
            print(f"FAIL: {type(e).__name__}: {e}")

    # Test B: @{theory "X"} — does it work if we use short name?
    print("\n=== Test B: @{theory} name lookup ===")
    async with Client(addr, 'HOL') as c:
        await c.set_trace(True)
        await c.add_lib(['MathBench_Prover.MathBench_Prover'])
        try:
            ret = await c.eval(
                'theory Test imports Main begin\n'
                'ML \\<open>val _ = @{theory "MathBench_Prover"}\\<close>\n'
                'end'
            )
            print("OK: short name works")
        except Exception as e:
            print(f"FAIL short name: {e}")

        # Also try the full qualified name
    async with Client(addr, 'HOL') as c:
        await c.set_trace(True)
        await c.add_lib(['MathBench_Prover.MathBench_Prover'])
        try:
            ret = await c.eval(
                'theory Test imports Main begin\n'
                'ML \\<open>val _ = @{theory "MathBench_Prover.MathBench_Prover"}\\<close>\n'
                'end'
            )
            print("OK: full name works")
        except Exception as e:
            print(f"FAIL full name: {e}")

asyncio.run(main())

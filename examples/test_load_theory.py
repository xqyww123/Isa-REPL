#!/bin/env python3
"""Test Client.load_theory() and Client.add_lib() semantics."""

import asyncio
import sys
sys.path.insert(0, '.')
from IsaREPL import Client

async def main():
    addr = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1:6666'

    # Test 1: load_theory builds theories and returns their full names
    print("=== Test 1: load_theory ===")
    async with Client(addr, 'HOL') as c:
        await c.set_trace(False)
        ret = await c.load_theory(['MathBench_Prover.MathBench_Prover', 'Minilang_Agent.Minilang_Agent'])
        assert ret == ['MathBench_Prover.MathBench_Prover', 'Minilang_Agent.Minilang_Agent'], f"Unexpected: {ret}"
        print("OK")

    # Test 2: add_lib makes theories auto-imported as ancestors
    print("=== Test 2: add_lib auto-imports ===")
    async with Client(addr, 'HOL') as c:
        await c.set_trace(True)
        await c.add_lib(['MathBench_Prover.MathBench_Prover', 'Minilang_Agent.Minilang_Agent'])
        ret = await c.eval(
            'theory Test imports Main begin\n'
            'ML \\<open>\n'
            'val ancestors = Context.ancestors_of @{theory}\n'
            '  |> map Context.theory_long_name;\n'
            'val has_mathbench = exists (fn n => String.isSubstring "MathBench" n) ancestors;\n'
            'val has_minilang = exists (fn n => String.isSubstring "Minilang" n) ancestors;\n'
            'val _ = @{assert} has_mathbench;\n'
            'val _ = @{assert} has_minilang;\n'
            '\\<close>\n'
            'end'
        )
        print("OK")

    # Test 3: add_lib theories accessible via @{theory} with short name
    print("=== Test 3: @{theory} short name lookup ===")
    async with Client(addr, 'HOL') as c:
        await c.set_trace(False)
        await c.add_lib(['MathBench_Prover.MathBench_Prover'])
        await c.eval(
            'theory Test imports Main begin\n'
            'ML \\<open>val _ = @{theory "MathBench_Prover"}\\<close>\n'
            'end'
        )
        print("OK")

    print("\nAll tests passed.")

asyncio.run(main())

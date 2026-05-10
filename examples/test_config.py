#!/bin/env python3
"""Test Client.config() for setting Isabelle configuration options."""

import asyncio
import sys
sys.path.insert(0, '.')
from IsaREPL import Client

async def main():
    addr = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1:6666'

    async with Client(addr, 'HOL') as c:
        await c.set_trace(True)

        await c.eval('theory Test imports Main begin')
        print("=== Theory loaded ===")

        # Test 1: Baseline
        await c.eval('lemma "1 + (1::nat) = 2"')
        ret = await c.eval('proof -')
        state0 = ret[0].state if ret else "no state"
        print(f"Baseline:\n{state0}\n")
        await c.eval('oops')

        # Test 2: config(show_types=true)
        await c.config(["show_types = true"])
        await c.eval('lemma "1 + (1::nat) = 2"')
        ret = await c.eval('proof -')
        state1 = ret[0].state if ret else "no state"
        print(f"After config(show_types=true):\n{state1}\n")
        await c.eval('oops')

        # Test 3: config(show_types=false)
        await c.config(["show_types = false"])
        await c.eval('lemma "1 + (1::nat) = 2"')
        ret = await c.eval('proof -')
        state2 = ret[0].state if ret else "no state"
        print(f"After config(show_types=false):\n{state2}\n")
        await c.eval('oops')

        # Test 4: eval(configs={"show_types": "true"})
        ret = await c.eval(
            'lemma "1 + (1::nat) = 2"\nproof -\noops',
            configs={"show_types": "true"}
        )
        state3 = ret[1].state if ret and len(ret) > 1 else "no state"
        print(f"eval(configs={{show_types:true}}):\n{state3}\n")

        # Test 5: After eval w/ configs, verify not persistent
        await c.eval('lemma "1 + (1::nat) = 2"')
        ret = await c.eval('proof -')
        state4 = ret[0].state if ret else "no state"
        print(f"After eval w/ configs (should revert):\n{state4}\n")
        await c.eval('oops')

        # Summary
        print("=== Summary ===")
        for label, state in [
            ("Baseline", state0),
            ("config(true)", state1),
            ("config(false)", state2),
            ("eval(configs)", state3),
            ("after eval(configs)", state4),
        ]:
            has_types = "(nat)" in state or ":: nat" in state or "::nat" in state
            print(f"  {label:25s} types visible: {has_types}")

asyncio.run(main())

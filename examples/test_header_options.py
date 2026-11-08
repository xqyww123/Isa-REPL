#!/usr/bin/env python3
"""Inline theory-header options (`options [...]`, including `condition`) in theories the REPL
evaluates itself, tested against a live `isabelle REPL` server under its default mute.

  test_header_options.py ADDR WORKDIR [CASE ...]

The server and this script share the file system (WORKDIR holds the \\005file fixtures).
"""

import asyncio
import os
import sys

from repl_test_harness import check, expect_fail, run_cases
from IsaREPL import Client

SKIPPED_THY = 'skipped theory: level 0'
SKIPPED_PRF = 'skipped proof: depth 0'
BODY = ('lemma l: False by simp\n'
        'ML \\<open>error "x"\\<close>\n'
        'definition c :: nat where "c = 1"\n')


def flags_false(out):
    f = out.flags
    return not (f.is_toplevel or f.is_theory or f.is_proof or f.has_goal)


def plugin_dict(out):
    p = out.plugin_output
    return dict(p) if isinstance(p, list) else (p or {})


class Run:
    def __init__(self, addr, workdir):
        self.addr = addr
        self.w = os.path.abspath(workdir)

    def client(self):
        return Client(self.addr, 'HOL', timeout=600)

    async def skipped(self, c, name, condition):
        outs = await c.eval(f'theory {name} imports Main options [condition = {condition}] begin\n'
                            + BODY + 'end')
        check(SKIPPED_THY in outs[0].state, f'header state: {outs[0].state!r}')
        lemma = next(o for o in outs if o.command.startswith('lemma'))
        check(SKIPPED_PRF in lemma.state and flags_false(lemma),
              f'lemma: {lemma.state!r} {lemma.flags}')
        for o in outs[1:-1]:
            check(not o.errors, f'{o.command}: {o.errors}')
            if not o.command.startswith('lemma'):
                check(SKIPPED_THY in o.state, f'{o.command}: {o.state!r}')
        await c.eval(f'theory {name}_b imports {name} begin')
        await expect_fail(c.fact(f'{name}.l'))
        await c.eval('end')

    async def t1_skip(self, c):
        await c.set_trace(True)
        await self.skipped(c, 'T1', 'false')
        await c.run_ML(None, 'if getenv "ISA_REPL_TEST_UNSET" = "" then () '
                             'else error "ISA_REPL_TEST_UNSET is set in the server"')
        await self.skipped(c, 'T1u', '"$ISA_REPL_TEST_UNSET"')

    async def t2_controls(self, c):
        for i, opts in enumerate(['options [condition = true]',
                                  'options [condition = "$ISABELLE_HOME"]', '']):
            # a failing \005eval leaves the state as before it: here, top level
            await expect_fail(c.eval(f'theory T2_{i} imports Main {opts} begin\n' + BODY + 'end'),
                              'Failed to apply initial proof method')

    async def t3_condition_proofs(self, c):
        await c.set_trace(True)
        outs = await c.eval('theory T3 imports Main options [condition_proofs = false] begin\n'
                            'lemma l: False by simp\n'
                            'definition c :: nat where "c = 1"')
        lemma = outs[1]
        check(SKIPPED_PRF in lemma.state and flags_false(lemma), f'lemma: {lemma.state!r}')
        check(await c.fact('l'), 'fact l')
        check(await c.fact('c_def'), 'the definition took effect')
        await c.eval('end')

    async def t4_precedence(self, c):
        sorry = 'lemma "x = (x::nat)" sorry'
        await expect_fail(c.eval('theory T4 imports Main options [quick_and_dirty = false] begin\n'
                                 + sorry))
        await c.eval('theory T4n imports Main begin\n' + sorry + '\nend')
        await c.eval('theory T4c imports Main options [quick_and_dirty = false] begin\n'
                     + sorry + '\nend', configs={'quick_and_dirty': 'true'})

    async def t5_no_inheritance(self, c):
        await c.eval('theory T5a imports Main options [condition_proofs = false] begin end')
        await c.eval('theory T5b imports Main options [quick_and_dirty = false] begin end')
        await c.eval('theory T5 imports T5a T5b begin')
        await expect_fail(c.eval('lemma "False" by simp'), 'Failed to apply initial proof method')
        await c.eval('lemma "x = (x::nat)" sorry')
        await c.eval('end')

    async def t6_continuation(self, c):
        await c.set_trace(True)
        await c.eval('theory T6a imports Main options [condition = false] begin\n'
                     'definition c :: nat where "c = 1"')
        outs = await c.eval('lemma l: False by simp')
        check(SKIPPED_PRF in outs[0].state, f'continued: {outs[0].state!r}')
        await c.eval('end')
        await c.eval('theory T6b imports Main options [quick_and_dirty = false] begin\n'
                     'lemma "True" by simp')
        await expect_fail(c.eval('lemma "x = (x::nat)" sorry'))
        await c.eval('end')

    async def t7_rollback(self, c):
        await c.eval('theory T7a imports Main options [quick_and_dirty = false] begin')
        await c.record_state('s4')
        await c.eval('end')
        await c.eval('theory T7b imports Main options [condition = false] begin')
        await c.record_state('s1')
        await c.eval('end')
        await c.eval('theory T7c imports Main begin end')
        await c.rollback('s4')
        await expect_fail(c.eval('lemma "x = (x::nat)" sorry'))
        await c.rollback('s1')
        await c.eval('lemma l: False by simp')

    async def t8_file_cache(self, c):
        """the \\005file cache restores the whole saved state: with `condition = false` the
        skip lives in the Toplevel node, not in the theory.  After the first call the option
        is blanked on disk (offsets unchanged), so only a resume from the cache still skips."""
        opts = 'options [condition = false]'
        text = ('theory F8 imports Main ' + opts + ' begin\n'
                'lemma a: "True" by simp\n'
                'lemma b: "True" by simp\n'
                'lemma bad: "False" by simp\n'
                'end\n')
        os.makedirs(os.path.join(self.w, 'hopt'), exist_ok=True)
        f = os.path.join(self.w, 'hopt', 'F8.thy')
        with open(f, 'w') as h:
            h.write(text)
        check(await c.file(f, line=3, column=0, cache_position=True) is None, 'first call')
        with open(f, 'w') as h:
            h.write(text.replace(opts, ' ' * len(opts)))
        check(await c.file(f, line=6, column=0, use_cache=True) is None, 'cached call')
        await expect_fail(c.file(f), 'Failed to apply initial proof method')

    async def t9_errors(self, c):
        for opts, needle in [
                ('[', ''),
                ('[foo = 1]', 'Bad system_option "foo"'),
                ('[quick_and_dirty = 5]', 'Malformed value for system option "quick_and_dirty"'),
                ('[condition = foo]', 'Condition "foo" cannot be evaluated'),
                ('[condition = "nope()"]', 'Bad theory condition predicate: "nope"')]:
            await expect_fail(c.eval(f'theory T9 imports Main options {opts} begin'), needle)
            await expect_fail(c.context(), 'Not in a proof context')   # still at top level

    async def t10_lex(self, c):
        for opts in ['[foo = 1]', '[condition = foo]']:
            cmds = await c.lex(f'theory T10 imports Main options {opts} begin\n'
                               'lemma "True" by simp\nend')
            check(len(cmds) >= 3, f'lex {opts}: {cmds}')
        h1 = await c.parse_thy_header('theory T10 imports Main options [quick_and_dirty] begin')
        h2 = await c.parse_thy_header('theory T10 imports Main begin')
        check(h1 == h2, f'thy_header: {h1} vs {h2}')

    async def t11_plugin(self, c):
        await c.set_trace(True)
        await c.plugin('QD', 'fn _ => fn _ => (SOME (MessagePackBinIO.Pack.packBool '
                             '(Options.default_bool "quick_and_dirty")), NONE)')
        outs = await c.eval('theory T11 imports Main options [quick_and_dirty = false] begin\n'
                            'lemma "True" by simp\nend')
        seen = [plugin_dict(o).get('QD') for o in outs[1:-1]]
        check(seen and all(v is False for v in seen), f'plugin saw {seen}')
        await c.unplugin('QD')

    async def t12_printing(self, c):
        await c.set_trace(True)
        for opts, shown in [('options [show_types]', True), ('', False)]:
            outs = await c.eval(f'theory T12 imports Main {opts} begin\nlemma "f x = f x"')
            st = outs[-1].state
            check(('variables:' in st) == shown, f'{opts!r} state: {st!r}')
            ctx = repr(await c.context())
            check(('::' in ctx) == shown, f'{opts!r} context: {ctx}')
            fact = ' '.join(await c.fact('refl'))
            check(('::' in fact) == shown, f'{opts!r} fact: {fact}')
            await c.eval('oops\nend')


CASES = ['t1_skip', 't2_controls', 't3_condition_proofs', 't4_precedence', 't5_no_inheritance',
         't6_continuation', 't7_rollback', 't8_file_cache', 't9_errors', 't10_lex',
         't11_plugin', 't12_printing']


def run(addr, workdir, names):
    r = Run(addr, workdir)

    async def case(name):
        async with r.client() as c:
            await c.set_trace(False)
            await getattr(r, name)(c)
    return run_cases(names or CASES, lambda name: asyncio.run(case(name)))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if run(sys.argv[1], sys.argv[2], sys.argv[3:]) else 1)

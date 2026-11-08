#!/usr/bin/env python3
"""Theory loading through the PIDE document, tested against a live `isabelle REPL` server.

  test_pide_loader.py setup WORKDIR
      writes the test session PL_Test under WORKDIR/root; then start the server with
      isabelle REPL -l HOL -o threads=8 -d WORKDIR/root -L WORKDIR/server.log ADDR OUTDIR
  test_pide_loader.py run ADDR WORKDIR [CASE ...]
      runs the cases (all by default) against that server, under its default mute

The server and this script share the file system.  A server serves one run: theories stay
loaded for the life of the process.  Every case ends with the loader's consistency check
(its table against the PIDE document).
"""

import asyncio
import os
import shutil
import subprocess
import sys
import uuid

from repl_test_harness import Failure, check, expect_fail, run_cases
from IsaREPL import Client

SESSION = 'PL_Test'


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def thy(name, imports, body=''):
    return f'theory {name} imports {imports} begin\n{body}\nend\n'


def lemmas(n):
    return '\n'.join(f'lemma l{i}: "({i}::nat) + 0 = {i}" by simp' for i in range(n))


def setup(workdir):
    root = os.path.join(workdir, 'root')
    shutil.rmtree(root, ignore_errors=True)
    write(os.path.join(root, 'ROOTS'), SESSION + '\n')
    write(os.path.join(root, SESSION, 'ROOT'),
          f'session {SESSION} = HOL +\n  theories H H2 H3\n')
    for name in ['H', 'H2', 'H3']:
        write(os.path.join(root, SESSION, name + '.thy'), thy(name, 'Main'))
    print(f'isabelle REPL -l HOL -o threads=8 -d {root} -L {workdir}/server.log ADDR OUTDIR')


async def ml(c, src):
    await c.run_ML(None, src)


async def loader_check(c, wait=10):
    """The loader's table against the document; waits up to `wait` seconds for a release in
    flight (an interrupted request releases asynchronously)."""
    await ml(c, f'''
      let
        val deadline = Time.now () + Time.fromSeconds {wait}
        fun loop () =
          let val r = Scala.function1 "isabelle_rpc.loader_check" ""
          in
            if not (String.isSubstring "INCONSISTENT" r) then ()
            else if Time.now () < deadline then (Time.sleep (Time.fromMilliseconds 200); loop ())
            else error ("loader_check: " ^ r)
          end
      in loop () end''')


async def not_pinned(c, name):
    await ml(c, f'''
      if member (op =) (Scala.function "isabelle_rpc.pinned_theories" []) {ml_str(name)}
      then error ("unexpectedly loaded: " ^ {ml_str(name)}) else ()''')


def ml_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


class Run:
    def __init__(self, addr, workdir):
        self.addr = addr
        self.w = os.path.abspath(workdir)
        self.d = os.path.join(self.w, 'thys')
        self.root = os.path.join(self.w, 'root', SESSION)
        self.isabelle_home = subprocess.run(
            ['isabelle', 'getenv', '-b', 'ISABELLE_HOME'], capture_output=True, text=True,
            check=True).stdout.strip()

    def client(self, qualifier='HOL', timeout=int(os.environ.get('PL_TEST_TIMEOUT', 1800))):
        return Client(self.addr, qualifier, timeout=timeout)

    def p(self, *parts):
        return os.path.join(self.d, *parts)

    # --- R8.4: the loader block -------------------------------------------------------

    async def workers(self, c):
        """max_threads + 4 simultaneous loads from Future workers (12 at threads=8), so that
        they outnumber the scheduler's threads: none may starve the document's own tasks"""
        await ml(c, f'''
          let
            val dir = Isabelle_System.make_directory (Path.explode {ml_str(self.p('workers'))})
            val names =
              map (fn i => "Worker" ^ string_of_int i) (0 upto Multithreading.max_threads () + 3)
            val _ = names |> List.app (fn name =>
              File.write (Path.append dir (Path.ext "thy" (Path.basic name)))
                ("theory " ^ name ^ " imports Main begin end\\n"))
            val futures =
              map (fn name => Future.fork (fn () =>
                Context.theory_long_name (hd (PIDE_Loader.use_theories "HOL" dir [name]))))
                names
            val deadline = Time.now () + Time.fromSeconds 600
            fun wait () =
              if forall Future.is_finished futures then ()
              else if Time.now () > deadline then error "workers: stuck after 600 s"
              else (Time.sleep (Time.fromMilliseconds 500); wait ())
            val _ = wait ()
            val got = map Future.join futures
          in
            if got = map (prefix "Draft.") names then () else error ("workers: " ^ commas got)
          end''')

    async def interrupt_sweep(self, c):
        """interrupts in the first 0-200 ms of a load land inside submit and await; the
        table stays consistent and a later load succeeds"""
        delays = list(range(0, 201, 10))
        for i, _ in enumerate(delays):
            write(self.p('intr', f'I{i}.thy'), thy(f'I{i}', 'Main', lemmas(1500)))
        for i, d in enumerate(delays):
            await ml(c, f'''
              let
                val dir = Path.explode {ml_str(self.p('intr'))}
                val th =
                  Isabelle_Thread.fork (Isabelle_Thread.params "intr" |> Isabelle_Thread.interrupts)
                    (fn () => ignore (Exn.capture_body (fn () =>
                      PIDE_Loader.use_theories "HOL" dir ["I{i}"])))
                val _ = Time.sleep (Time.fromMilliseconds {d})
                val _ = Isabelle_Thread.interrupt_thread th
              in Isabelle_Thread.join th end''')
            await loader_check(c)
            r = await c.load_theory([self.p('intr', f'I{i}')])
            check(r == [f'Draft.I{i}'], f'd={d}: later load gave {r}')

    async def interrupt_releases(self, c):
        """an interrupt ends the waiting: the request leaves the table as it found it,
        although its theory never finishes, and the next request reads the file again"""
        stuck = self.p('stuck')
        write(os.path.join(stuck, 'Stuck.thy'),
              thy('Stuck', 'Main', 'ML \\<open>Time.sleep (Time.fromSeconds 600)\\<close>'))
        await ml(c, f'''
          let
            fun table () =
              Scala.function1 "isabelle_rpc.loader_check" ""
              |> space_explode " " |> hd |> unprefix "table=" |> Value.parse_nat
            fun wait_for what p =
              let
                val deadline = Time.now () + Time.fromSeconds 30
                fun loop () =
                  if p (table ()) then ()
                  else if Time.now () < deadline then (Time.sleep (Time.fromMilliseconds 100); loop ())
                  else error ("interrupt_releases: " ^ what)
              in loop () end
            val n = table ()
            val th =
              Isabelle_Thread.fork (Isabelle_Thread.params "intr" |> Isabelle_Thread.interrupts)
                (fn () => ignore (Exn.capture_body (fn () =>
                  PIDE_Loader.use_theories "HOL" (Path.explode {ml_str(stuck)}) ["Stuck"])))
            val _ = wait_for "the request never entered the table" (fn m => m = n + 1)
            val _ = Isabelle_Thread.interrupt_thread th
            val _ = Isabelle_Thread.join th
          in wait_for "the interrupted request was not released" (fn m => m = n) end''')
        write(os.path.join(stuck, 'Stuck.thy'), thy('Stuck', 'Main'))
        check(await c.load_theory([os.path.join(stuck, 'Stuck')]) == ['Draft.Stuck'], 'later load')

    async def frozen(self, c):
        """read once: a loaded file and its ML_file are not re-read when an importer loads"""
        d_body = 'ML_file \\<open>d.ML\\<close>\nML \\<open>val d_thy = {}\\<close>'
        write(self.p('frz', 'd.ML'), 'val d_value = 1;\n')
        write(self.p('frz', 'D.thy'), thy('D', 'Main', d_body.format(1)))
        write(self.p('frz', 'E.thy'),
              thy('E', 'D', 'ML \\<open>\\<^assert> (d_value = 1 andalso d_thy = 1)\\<close>'))
        check(await c.load_theory([self.p('frz', 'D')]) == ['Draft.D'], 'D')
        write(self.p('frz', 'd.ML'), 'val d_value = 2;\n')
        write(self.p('frz', 'D.thy'), thy('D', 'Main', d_body.format(2)))
        check(await c.load_theory([self.p('frz', 'E')]) == ['Draft.E'], 'E')
        check(await c.load_theory([self.p('frz', 'D')]) == ['Draft.D'], 'D again')

    async def header_changed(self, c):
        """a held file's header is read from the table (with_thy_reader), also when the file
        changed or is gone"""
        write(self.p('hdr', 'F.thy'), thy('F', 'Main'))
        write(self.p('hdr', 'Fresh.thy'), thy('Fresh', 'Main'))
        write(self.p('hdr', 'G.thy'), thy('G', 'F'))
        write(self.p('hdr', 'G2.thy'), thy('G2', 'F'))
        check(await c.load_theory([self.p('hdr', 'F')]) == ['Draft.F'], 'F')
        write(self.p('hdr', 'F.thy'), thy('F', 'Main Fresh'))
        check(await c.load_theory([self.p('hdr', 'G')]) == ['Draft.G'], 'G')
        await not_pinned(c, 'Draft.Fresh')
        os.remove(self.p('hdr', 'F.thy'))
        check(await c.load_theory([self.p('hdr', 'G2')]) == ['Draft.G2'], 'G2 after F deleted')

    async def session_file_deleted(self, c):
        """a held session theory keeps its node when its file is gone (find_theory_node)"""
        check(await c.load_theory([f'{SESSION}.H2']) == [f'{SESSION}.H2'], 'H2')
        os.remove(os.path.join(self.root, 'H2.thy'))
        check(await c.load_theory([f'{SESSION}.H2']) == [f'{SESSION}.H2'], 'by qualified name')
        async with self.client(SESSION) as c2:
            check(await c2.load_theory(['H2'], SESSION) == [f'{SESSION}.H2'],
                  'unqualified, under the session qualifier, from another directory')
        write(self.p('sdel', 'Imp.thy'), thy('Imp', f'"{SESSION}.H2"'))
        check(await c.load_theory([self.p('sdel', 'Imp')]) == ['Draft.Imp'], 'importer')
        await expect_fail(c.load_theory([f'{SESSION}.Nope']), f'{SESSION}.Nope')

    async def no_end(self, c):
        """a theory without `end` fails instead of hanging"""
        write(self.p('noend', 'NoEnd.thy'), 'theory NoEnd imports Main begin\nlemma "True" by simp\n')
        await expect_fail(c.load_theory([self.p('noend', 'NoEnd')]), 'Draft.NoEnd')

    # --- R8.3: through the server and the client -----------------------------------------

    async def multiset(self, c):
        check(await c.load_theory(['HOL-Library.Multiset']) == ['HOL-Library.Multiset'], 'Multiset')

    async def dir_by_path(self, c):
        write(self.p('dir', 'A.thy'), thy('A', 'Main', 'definition "a_const = (1::nat)"'))
        write(self.p('dir', 'B.thy'), thy('B', 'A', 'lemma "a_const = 1" by (simp add: a_const_def)'))
        check(await c.load_theory([self.p('dir', 'B')]) == ['Draft.B'], 'B')
        check(await c.load_theory([self.p('dir', 'A')]) == ['Draft.A'], 'A')

    async def failing_proof(self, c):
        write(self.p('bad', 'Bad.thy'), thy('Bad', 'Main', 'lemma "False" by simp'))
        await expect_fail(c.load_theory([self.p('bad', 'Bad')]),
                          'Draft.Bad', 'Failed to apply initial proof method', 'Bad.thy')

    async def missing_file(self, c):
        await expect_fail(c.load_theory([self.p('missing', 'Missing')]), 'Missing.thy')

    async def empty_file(self, c):
        write(self.p('empty', 'Empty.thy'), '')
        await expect_fail(c.load_theory([self.p('empty', 'Empty')]),
                          'Empty theory file', 'theory "Draft.Empty"')

    async def late_file(self, c):
        """a loaded file missing when the request enters the table fails the request, naming
        the theory that loads it (here an import of the requested theory), even if that theory
        creates the file before loading it: every loaded file is read once, at entry"""
        late = self.p('late', 'late.ML')
        if os.path.exists(late):
            os.remove(late)
        create = f'File.write (Path.explode {ml_str(late)}) "val late = 1;"'
        write(self.p('late', 'Late.thy'),
              thy('Late', 'Main',
                  f'ML \\<open>{create}\\<close>\nML_file \\<open>late.ML\\<close>'))
        write(self.p('late', 'LateTop.thy'), thy('LateTop', 'Late'))
        await expect_fail(c.load_theory([self.p('late', 'LateTop')]),
                          'late.ML', 'The error(s) above occurred for theory "Draft.Late"')
        await not_pinned(c, 'Draft.Late')

    async def malformed_header(self, c):
        write(self.p('mal', 'Mal.thy'), 'theory Mal imports begin\nend\n')
        await expect_fail(c.load_theory([self.p('mal', 'Mal')]))

    async def symlink(self, c):
        """the same file through a symlink is one node, named and placed by its real path"""
        write(self.p('real', 'S1.thy'), thy('S1', 'Main'))
        link = self.p('link')
        if not os.path.islink(link):
            os.symlink(self.p('real'), link)
        check(await c.load_theory([os.path.join(link, 'S1')]) == ['Draft.S1'], 'through the link')
        check(await c.load_theory([self.p('real', 'S1')]) == ['Draft.S1'], 'by the real path')
        path = await c.path_of_theory('Draft.S1', self.d)
        check(path == os.path.realpath(self.p('real', 'S1.thy')), f'path {path}')
        await ml(c, '''
          let val n = length (filter (fn s => s = "Draft.S1")
                (Scala.function "isabelle_rpc.pinned_theories" []))
          in if n = 1 then () else error ("Draft.S1 held " ^ string_of_int n ^ " times") end''')

    async def import_order(self, c):
        """\\005load answers by position: loaded file, heap, connection table, loaded by name"""
        write(self.p('ord', 'O1.thy'), thy('O1', 'Main'))
        await c.set_trace(False)
        await c.eval('theory CT imports Main begin end')
        r = await c.load_theory([self.p('ord', 'O1'), 'Main', 'HOL.CT', 'HOL-Library.Multiset'], 'HOL')
        check(r == ['Draft.O1', 'Main', 'HOL.CT', 'HOL-Library.Multiset'], f'order {r}')

    async def concurrent_clients(self, c):
        sets = [['HOL-Library.Lattice_Algebras', 'HOL-Library.Finite_Lattice'],
                ['HOL-Library.Finite_Lattice', 'HOL-Library.Dual_Ordered_Lattice'],
                ['HOL-Library.Dual_Ordered_Lattice', 'HOL-Library.Lattice_Constructions'],
                ['HOL-Library.Lattice_Constructions', 'HOL-Library.Lattice_Algebras']]

        async def one(names):
            async with self.client() as ci:
                return await ci.load_theory(names)
        got = await asyncio.gather(*(one(s) for s in sets))
        check(got == sets, f'concurrent: {got}')

    async def client_timeout(self, c):
        """a client gives up during a load and kills its connection, which interrupts the load;
        the table stays consistent and a later load succeeds (that the interrupt releases the
        request is interrupt_releases' job)"""
        target = 'HOL-Library.Extended_Real'
        cid = None
        try:
            async with self.client(timeout=3) as ct:
                cid = ct.client_id
                await ct.load_theory([target])
            raise Failure('the load finished within 3 s; choose a bigger theory')
        except TimeoutError:
            pass
        await Client.kill_client(self.addr, cid)
        await loader_check(c, wait=30)
        check(await c.load_theory([target]) == [target], 'later load')

    # --- R11: a loaded file is named by its folder ------------------------------------

    async def session_file_one_name(self, c):
        """one session file by path under qualifier HOL, by qualified name, through a
        symlink: one node, one name (the first request is by path)"""
        h = os.path.join(self.root, 'H')
        check(await c.load_theory([h], 'HOL') == [f'{SESSION}.H'], 'by path, qualifier HOL')
        check(await c.load_theory([f'{SESSION}.H']) == [f'{SESSION}.H'], 'by name')
        link = self.p('sesslink')
        if not os.path.islink(link):
            os.symlink(self.root, link)
        check(await c.load_theory([os.path.join(link, 'H')], 'HOL') == [f'{SESSION}.H'], 'link')

    async def heap_source_by_path(self, c):
        lst = os.path.join(self.isabelle_home, 'src', 'HOL', 'List')
        check(await c.load_theory([lst], SESSION) == ['HOL.List'], 'qualifier PL_Test')
        check(await c.load_theory([lst], 'HOL') == ['HOL.List'], 'qualifier HOL')

    async def two_drafts(self, c):
        write(self.p('x1', 'Dup.thy'), thy('Dup', 'Main'))
        write(self.p('x2', 'Dup.thy'), thy('Dup', 'Main'))
        check(await c.load_theory([self.p('x1', 'Dup')]) == ['Draft.Dup'], 'first')
        await expect_fail(c.load_theory([self.p('x2', 'Dup')]),
                          self.p('x1', 'Dup.thy'), self.p('x2', 'Dup.thy'), '-d')

    async def deleted_draft_keeps_name(self, c):
        write(self.p('kdel', 'K.thy'), thy('K', 'Main'))
        check(await c.load_theory([self.p('kdel', 'K')]) == ['Draft.K'], 'K')
        os.remove(self.p('kdel', 'K.thy'))
        check(await c.load_theory([self.p('kdel', 'K')]) == ['Draft.K'], 'K after deletion')

    async def draft_imports_list(self, c):
        """inside a Draft file, a short import of a HOL theory must be qualified"""
        write(self.p('ul', 'UL.thy'), thy('UL', 'List'))
        await expect_fail(c.load_theory([self.p('ul', 'UL')]))

    # --- R4: the mute applies to the REPL world only -------------------------------------

    async def mute(self, c):
        mark = uuid.uuid4().hex
        write(self.p('mute', 'Mark.thy'),
              thy('Mark', 'Main', f'ML \\<open>writeln "LOADED_{mark}"\\<close>'))
        check(await c.load_theory([self.p('mute', 'Mark')]) == ['Draft.Mark'], 'Mark')
        await c.set_trace(False)
        await c.eval(f'theory RM imports Main begin\nML \\<open>writeln "REPL_{mark}"\\<close>\nend')
        await asyncio.sleep(2)
        with open(os.path.join(self.w, 'server.log')) as f:
            log = f.read()
        check(f'LOADED_{mark}' in log, "a loaded theory's own message is not in the -L file")
        check(f'REPL_{mark}' not in log, 'a REPL-world message leaked into the -L file')


CASES = ['workers', 'multiset', 'dir_by_path', 'failing_proof', 'missing_file', 'empty_file',
         'late_file', 'malformed_header', 'symlink', 'import_order', 'session_file_one_name',
         'heap_source_by_path', 'two_drafts', 'deleted_draft_keeps_name', 'draft_imports_list',
         'frozen', 'header_changed', 'session_file_deleted', 'no_end', 'mute',
         'interrupt_sweep', 'interrupt_releases', 'concurrent_clients', 'client_timeout']


def run(addr, workdir, names):
    r = Run(addr, workdir)

    async def case(name):
        async with r.client() as c:
            await getattr(r, name)(c)
            await loader_check(c)
    return run_cases(names or CASES, lambda name: asyncio.run(case(name)))


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'setup':
        setup(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == 'run':
        sys.exit(0 if run(sys.argv[2], sys.argv[3], sys.argv[4:]) else 1)
    else:
        print(__doc__)
        sys.exit(2)

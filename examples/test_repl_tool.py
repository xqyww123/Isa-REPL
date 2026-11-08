#!/usr/bin/env python3
"""The `isabelle REPL` tool around its boot load, tested by starting and stopping servers.

  test_repl_tool.py WORKDIR [CASE ...]

Needs `isabelle` on PATH with Isabelle_RPC and Isa-REPL registered, and the HOL heap built.
Every server it starts runs under an outer wall-clock bound and is gone when a case ends.
"""

import os
import signal
import subprocess
import sys
import threading
import time

from repl_test_harness import check, run_cases

PORT = 6790


class Server:
    """`isabelle REPL` as a child process; stderr lines are kept with their arrival times"""

    def __init__(self, workdir, name, args, wall=900):
        self.out = os.path.join(workdir, 'tool', name)
        os.makedirs(self.out, exist_ok=True)
        self.proc = subprocess.Popen(
            ['timeout', '-k', '10', str(wall), 'isabelle', 'REPL', *args,
             f'127.0.0.1:{PORT}', self.out],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.lines = []
        self.threads = [threading.Thread(target=self._read, args=(s,), daemon=True)
                        for s in (self.proc.stdout, self.proc.stderr)]
        for t in self.threads:
            t.start()

    def _read(self, stream):
        for line in stream:
            self.lines.append((time.time(), line.rstrip('\n')))

    def wait_line(self, needle, limit):
        deadline = time.time() + limit
        while time.time() < deadline:
            for t, line in list(self.lines):
                if needle in line:
                    return t
            if self.proc.poll() is not None:
                break
            time.sleep(0.2)
        return None

    def wait_exit(self, limit):
        try:
            rc = self.proc.wait(limit)
        except subprocess.TimeoutExpired:
            return None, None
        for t in self.threads:
            t.join(5)
        return rc, time.time()

    def text(self):
        return '\n'.join(line for _, line in self.lines)

    def jvm_pid(self):
        """the tool's JVM: its command line names this server's output directory"""
        for pid in os.listdir('/proc'):
            try:
                with open(f'/proc/{pid}/cmdline', 'rb') as f:
                    cmd = f.read().split(b'\0')
            except OSError:
                continue
            if os.path.basename(cmd[0]) == b'java' and b'isabelle.Isabelle_Tool' in cmd and \
               self.out.encode() in cmd:   # the JVM, not the bash script that starts it
                return int(pid)
        return None

    def ml_pids(self, jvm):
        """the ML processes of that JVM: the tool puts its pid into their REPL_PID"""
        found = set()
        for pid in os.listdir('/proc'):
            try:
                with open(f'/proc/{pid}/environ', 'rb') as f:
                    env = f.read().split(b'\0')
            except OSError:
                continue
            if f'REPL_PID={jvm}'.encode() in env:
                found.add(int(pid))
        return found

    def stop(self):
        """SIGTERM to the JVM first: Isabelle then ends the processes it started (its
        Naproche server, which SIGKILL leaves behind); SIGKILL only what is left after 15 s"""
        jvm = self.jvm_pid()
        ml = self.ml_pids(jvm) if jvm else set()
        if jvm:
            try:
                os.kill(jvm, signal.SIGTERM)
                self.proc.wait(15)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
        for pid in ml:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.proc.wait()


def t_expiry(w):
    """-T expiry: the timeout message, a non-zero exit within seconds, no process left"""
    s = Server(w, 'expiry', ['-l', 'HOL', '-T', '1'])
    try:
        t_msg = s.wait_line('timed out after 1s waiting for load', 600)
        check(t_msg is not None, 'no timeout message:\n' + s.text())
        jvm = s.jvm_pid()
        check(jvm is not None, 'no JVM found')
        rc, t_exit = s.wait_exit(60)
        check(rc not in (None, 0), f'rc {rc}')
        check(t_exit - t_msg < 15, f'exit {t_exit - t_msg:.1f}s after the message')
        time.sleep(2)
        left = (s.ml_pids(jvm) if jvm else set()) | ({jvm} if jvm and os.path.exists(f'/proc/{jvm}') else set())
        check(not left, f'processes left: {left}')
        # no error line from the boot thread after the timeout (Output.error_message: ***)
        after = [l for t, l in s.lines if t > t_msg and '***' in l]
        check(not after, f'error lines after the timeout message: {after}')
    finally:
        s.stop()


def t_kill_ml(w):
    """kill -9 of the ML process during the boot load: the tool reports it and exits
    (-l Pure: the boot load then loads HOL too, for minutes)"""
    s = Server(w, 'kill', ['-l', 'Pure'])
    try:
        check(s.wait_line('Isa-REPL on', 600) is not None, 'no launch line:\n' + s.text())
        deadline = time.time() + 600
        pids = set()
        while not pids and time.time() < deadline:
            jvm = s.jvm_pid()
            pids = s.ml_pids(jvm) if jvm else set()
            time.sleep(0.5)
        check(pids, 'no ML process found')
        time.sleep(20)
        check(s.proc.poll() is None and not any('server ready' in l for _, l in s.lines),
              'the boot load ended before the kill')
        t_kill = time.time()
        for p in pids:
            os.kill(p, signal.SIGKILL)
        rc, t_exit = s.wait_exit(60)
        check(rc not in (None, 0), f'rc {rc}')
        check(t_exit - t_kill < 15, f'exit {t_exit - t_kill:.1f}s after the kill')
        check('Isabelle process terminated' in s.text() and 'KILL' in s.text(),
              'no termination message:\n' + s.text())
    finally:
        s.stop()


def t_logic_with_isa_repl(w):
    """-l a logic whose heap holds Isa_REPL: the boot load answers from the heap"""
    s = Server(w, 'heap', ['-l', 'Isa_REPL'], wall=3600)
    try:
        t0 = s.wait_line('Isa-REPL on', 3000)
        t1 = s.wait_line('server ready', 3000)
        check(t0 is not None and t1 is not None, 'not ready:\n' + s.text())
        print(f'    ready {t1 - t0:.1f}s after the launch line (includes any heap build)')
    finally:
        s.stop()


CASES = {'expiry': t_expiry, 'kill_ml': t_kill_ml, 'logic_with_isa_repl': t_logic_with_isa_repl}


def main(workdir, names):
    return run_cases(names or list(CASES), lambda name: CASES[name](os.path.abspath(workdir)))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if main(sys.argv[1], sys.argv[2:]) else 1)

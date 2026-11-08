"""The harness of the test scripts in examples/: one PASS or FAIL line per case, then the
summary, whatever a case raises."""

import os
import sys
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from IsaREPL import REPLFail


class Failure(Exception):
    pass


def check(cond, msg):
    if not cond:
        raise Failure(msg)


async def expect_fail(coro, *needles):
    """the REPL error of `coro`, which must contain every needle"""
    try:
        r = await coro
    except REPLFail as e:
        text = str(e)
        for n in needles:
            check(n in text, f'the error lacks {n!r}: {text}')
        return text
    raise Failure(f'expected an error, got {r!r}')


def run_cases(names, case):
    """`case(name)` for each name; any exception fails that case only (Ctrl-C still stops
    the run), with a traceback on stderr unless it is a Failure or a REPLFail.
    True if every case passed."""
    failed = []
    for name in names:
        try:
            case(name)
            print(f'PASS {name}', flush=True)
        except Exception as e:
            failed.append(name)
            if not isinstance(e, (Failure, REPLFail)):
                traceback.print_exc()
            print(f'FAIL {name}: {type(e).__name__}: {e}', flush=True)
    print(f'{len(names) - len(failed)} passed, {len(failed)} failed' +
          (': ' + ' '.join(failed) if failed else ''), flush=True)
    return not failed

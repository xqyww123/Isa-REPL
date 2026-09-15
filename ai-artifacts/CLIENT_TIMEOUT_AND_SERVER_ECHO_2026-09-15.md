# Two small defects noticed by the guard-cache STEP 5 review (2026-09-15) — recorded, not fixed

Found by the review of `phi-system/ai-artifacts/step5` (its report:
`contrib/phi-system/ai-artifacts/step5/STEP5_REVIEW_2026-09-14.md`, proposal P-4).
The author asked for a record, not a fix ("你写个报告到文件记录一下吧").  Neither
affects the STEP 5 numbers: both were identical across every leg.

## 1. `Client.__init__`'s `timeout` is stored and never read

`IsaREPL/IsaREPL.py:132` — `def __init__(self, addr, thy_qualifier, timeout: int | None = 3600)`;
`:142` — `self.timeout = timeout`.  That is the only occurrence of `self.timeout` in the
file: no method consults it.  The per-call timeouts (`eval(..., timeout=, cmd_timeout=)`,
`file(..., timeout=)`) are separate arguments sent to the server; the constructor's
value governs nothing.  A caller who passes `timeout=None` (as the STEP 5 harness did,
meaning "no cap") or `timeout=60` gets the same behaviour: no client-side cap at all.

Two consistent fixes: implement it (apply it as the default for `eval`/`file`'s
`timeout` when the call passes none, or as an `asyncio.wait_for` bound on every
request), or delete the parameter so the signature stops promising a safeguard.

## 2. `repl_server.sh` echoes a command line that is not the one it runs

`repl_server.sh:127` prints `isabelle build -D $DIR $options REPL$$`; `:128` executes
`REPL_DEFAULT_SESSION=... REPL_PID=$$ isabelle build -o quick_and_dirty=true -D $DIR
$options REPL$$`.  The echoed line lacks `-o quick_and_dirty=true` and the two
environment variables, so a server log records a build configuration that is not the
build's.  Fix: build the command once (an array), echo it, run it — e.g.

    cmd=(isabelle build -o quick_and_dirty=true -D "$DIR" $options "REPL$$")
    echo REPL_DEFAULT_SESSION="$BASE_SESSION" REPL_PID=$$ "${cmd[@]}"
    REPL_DEFAULT_SESSION="$(printf '%b' $BASE_SESSION)" REPL_PID=$$ "${cmd[@]}"

(`$options` is a whitespace-joined string today; keeping it unquoted preserves the
current word splitting.)

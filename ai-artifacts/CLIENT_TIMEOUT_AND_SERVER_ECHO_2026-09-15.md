# Two small defects noticed by the guard-cache STEP 5 review (2026-09-15) — recorded 2026-09-15, resolved 2026-09-30

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

## Resolution (2026-09-30)

**Item 1 was a regression, not a dead parameter, and is fixed.**  Before the asyncio
migration (`c23aee2`) the constructor's `timeout` went to
`socket.create_connection((host, port), timeout=timeout)`: a socket timeout in seconds,
bounding the connect and every later blocking read, raising `socket.timeout`
(= `TimeoutError` since Python 3.10).  The migration replaced the socket with
`asyncio.open_connection` / `reader.read` and dropped the bound.  The callers were
written against the old meaning and still are: `evaluation/evaluator.py` passes
`timeout=max(connection_timeout, timeout + 20)` and catches `TimeoutError` around
its REPL calls in about ten places; `AoA/test.py`, `evaluation/autocorrode.py` and
the Semantic_Embedding tests pass seconds too, and `PlainAgent/run_case.py` did
until this fix (budget + 900 s).
(`IsaMini/REPL.py:49` forwards a value as well, but that line cannot run today:
the module's `class REPL:` shadows its `import IsaREPL as REPL`, so `REPL.Client`
raises `AttributeError` — an unrelated, pre-existing bug reported to the author.)
Until today none of those handlers could fire.

The same migration dropped the `timeout` of `Client.test_server` and
`Client.kill_client` as well; the record above missed them.  Each of the two also
carried its own copy of the whole one-shot exchange (connect, send, read, close).

Fix (ruled 2026-09-30, "赞同你的建议"; extended the same day by the review's F5,
"接受建议", and by its F9, the merge of the one-shot exchange, which the drafter made
at the review's recommendation without a separate ruling; the review's F4, a kill on
timeout, was accepted and then retracted, see below): the read loop is one static
helper,
`Client._read_object(reader, unpack, timeout)`, whose every chunk read is
`asyncio.wait_for(reader.read(65536), timeout)`; the one-shot exchange is one
private classmethod, `Client._request_once(addr, message, timeout)`, whose connect is
wrapped in `asyncio.wait_for(asyncio.open_connection(...), timeout)`, and
`test_server` / `kill_client` are one-line wrappers over it; `__aenter__` wraps its
connect the same way.  `_feed_and_unpack` calls the helper with `self.timeout`; a
read that does not finish for any reason (the client's own timeout, a caller-side
`asyncio.wait_for`, `task.cancel()`, a reset) closes the client before re-raising —
the stream is then out of step (a late reply would be read as the answer to the next
request) and the protocol has no request ids to resync on, so later calls fail with
`REPLFail("... is dead or closed")` instead of returning the wrong reply.  No
`kill <id>` is sent: the review's F4 proposed one on the client's own timeout (as the
pre-migration `close()` sent on every close, a call the asyncio migration dropped
without a word), the author accepted it and retracted it the same day ("强烈反对！…
客服端自己超时是这个连接的事情"; "好，撤回 F4") — a client timeout is this
connection's decision, and stopping the server-side request is the caller's policy,
for which `Client.kill_client(addr, id)` remains the explicit API.  `timeout=None`
still waits forever.  The client's own timeout on a read carries the socket-era
message `'timed out'` (raised at the read site, `from None`; a connect timeout, like
a caller-imposed one, keeps asyncio's empty message), which
`evaluation/failure_analysis.py:36` matches, so on a read the two can be told apart
(review G2, "赞同你的建议").
The constructor docstring names the unit (seconds; `eval`/`file` take milliseconds).

Verified against the live server on `127.0.0.1:6666` with
`ai-artifacts/client_timeout_probe.py` (kept on disk, not committed): heartbeat and a
normal `eval` work; an `eval` whose reply is late raises `TimeoutError` at the cap
(2.0 s), the next call raises `REPLFail`, the client is gone from `Client.clients`;
a connect to a non-routable address raises `TimeoutError` at the cap (1.0 s) from
both the constructor path and `test_server`; `kill_client` on a live client returns
`True`; `timeout=None` waits out a 3 s command; a caller-side `asyncio.wait_for` and
a `task.cancel()` each close the client.  Negative control,
`ai-artifacts/client_timeout_negative_control.py` run against the client as
committed before the fix: with a 2 s cap a 5 s command returned after the full
5 s (the cap was ignored), and after a caller-side cancel the next request was
answered with the previous command's reply.

The callers that the restored cap would have broken were fixed with it (the
review's F1–F3, rulings of 2026-09-30: F1 "好的，那么就不给超时了", F2 "可以改",
F3 "接受全部建议"), including the one in another module:
`contrib/Semantic_Embedding/Test/test_resolve_notation_e2e.py:140` built its client
with a 120 s cap around an `eval` whose server-side budget is 300 s (line 142), so a
valid run of 120–300 s would have raised `TimeoutError`; its cap is now 360 s
(review F6, "随你便").

The agent evaluators (`evaluation/evaluator.py` `MinilangAgent_Base`, and
`PlainAgent_Base` through it) and `PlainAgent/run_case.py` now pass no cap, because
the whole agent run is one reply and its budget-exempt waits (quota pauses of 20 min)
have no bound; the author chose this over a backstop of budget + 30 min or 2 × budget.
Even without a quota pause the budget overruns, since it is checked by polling: the
fleet DB holds a run of 14 425 s with no quota wait, against a would-be cap of
14 420 s.  `evaluation/autocorrode.py` derives its client cap (1200 s) and its
verification eval's server cap (600 s) from one constant, since the server's timer
starts later and stretches with GC pauses and `timeout_scale`.  The harness's attempt
loops stop after a `TimeoutError` (the client is closed), and its worker loop no
longer skips the statistics update on a `REPLFail` (that skip left `remaining_cases`
stuck and the run waiting forever — a pre-existing bug).  One accepted consequence
remains: after a client timeout on an Isar evaluator the worker still holds the
closed client, so the next case is recorded CASE_NOT_AVAILABLE without being
attempted (not reused from the result DB, so a resumed run retries it) before the
worker reconnects; reconnecting first is the review's F3 item (iii), not done, and
the attempt loop's stop after a timeout, item (ii), is kept — both on the drafter's
recommendation, which the author took ("按你建议的来吧", 2026-09-30).
Simulation: `ai-artifacts/client_timeout_harness_sim.py` (kept on disk, not
committed), one fake evaluator raising `REPLFail` on the first of three cases —
with the edited harness the run terminates with {c1: CASE_NOT_AVAILABLE,
c2: SUCCESS, c3: SUCCESS} after one reconnect; with the harness as last committed
(`git show 2dbb65a4:evaluation/evaluator.py`, passed as the script's argument) it
hangs past 20 s.

**Item 2 is moot.**  `repl_server.sh` was deleted at `c4a63ad` ("Code-review
follow-ups: delete the repl_server.sh shim"); the `isabelle REPL` tool replaced it.
Whether the tool echoes its build command faithfully was not checked.

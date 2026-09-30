<!-- Judge report of the two-turn adversarial review (workflow wf_f988c11a-81f, 16 agents, claude-opus-5-5 at xhigh, 2026-09-30).  The drafter re-verified F1 (fleet DB: putnam_1962_b6 elapsed 14 425 068 ms), F2 (autocorrode.py:145/283), F3 (evaluator.py:1036-1094, :507-509), F4 (c23aee2^ close(); Server.ML:284-294), F6 (test_resolve_notation_e2e.py:140/142) and the §6 IsaMini/REPL.py shadowing (AttributeError reproduced) before reporting to the author.  Triage decisions are the author's; see the conversation of 2026-09-30. -->

# Judge report: restoring the client-side timeout of `IsaREPL.Client` (2026-09-30)

## 1. Verdict: MET_ON_CONDITION

**What the change is.** The change makes the constructor argument `Client(addr, thy_qualifier, timeout)` take effect again. It bounds the connect and each chunk of every reply by `timeout` seconds. On a timeout, `_feed_and_unpack` closes the client and re-raises `TimeoutError`. `test_server` and `kill_client` now share the read-loop helper `_read_object`. I re-read the diff against `IsaREPL/IsaREPL.py` and the relevant asyncio semantics, and the code inside `IsaREPL.py` is correct.

**Why it cannot land by itself.** Several callers chose their timeout values between April and September 2026. During that time the parameter did nothing, so those values have never been tested. Switching the parameter on switches on those values, and two of them are wrong in a way that breaks production work:

- **F1.** The AoA/PlainAgent evaluation fleet would cut off legitimate agent runs. I read the fleet's own state DB (`tools/aoa_putnam_eval/state/putnam_deepseekv4pro.db`, read-only). `putnam_1962_b6` ran 14 425 068 ms, which is past the 14 420 s cap. It had zero quota pauses.
- **F2.** autocorrode would kill its only verification client the first time a verification reaches its own server-side cap.

**Conditions for acceptance.** All five must hold:

1. **C1 (F1).** The author approves a fix for the callers that host an agent run: `evaluation/evaluator.py` (MinilangAgent_Base, and PlainAgent_Base through it) and `contrib/Isa-Mini/PlainAgent/run_case.py`. That fix lands in the same change as the Client fix, or before it. The author also chooses between no client cap and a generous backstop.
2. **C2 (F2).** The author approves the autocorrode fix, and it lands together with the Client fix. The fix derives the client cap from the verification eval's server cap, with a generous margin.
3. **C3 (F3).** The author sees what a client timeout actually does in the evaluation harness, which differs from what the brief says, and confirms again that closing the client on a timeout is still wanted.
4. **C4 (F4, F5).** The author decides two extensions of the ruled close. F4: send one best-effort `kill <id>` on the client's own timeout. F5: close the client on any read that does not finish, not only on the client's own timeout. I recommend adopting both. If the author declines them, the change is still acceptable.
5. **C5 (F6, F8, F9).** The drafter fixes these (the resolve-notation test cap, a hand-edited record, and merging the two copies of the one-shot exchange), and the result goes back to review.

## 2. Accepted findings

### F1: the reactivated cap cuts off legitimate agent runs (blocker, AUTHOR)

**The chain, verified end to end.**
- `evaluator.py:463` passes `timeout = connection_timeout = max(60, timeout_seconds)`. Line 301 then builds `Client(..., timeout=max(connection_timeout, timeout + 20))`, which is the agent budget + 20 s.
- The harness reads the whole agent run as one reply (`_write` at :531, then one `_feed_and_unpack()` at :537). So the per-chunk bound covers the whole run.
- The agent budget counts only working time. `language_model_driver.py:_quota_pause` does `with self.budget_exempt(): await asyncio.sleep(1200)`, so each quota pause adds 1200 s of wall-clock time that the budget does not count.
- Even with no pause, the budget check is polled, so a run finishes a few seconds after the budget expires. That is the 1962_b6 case above.
- When the cap fires, :569-570 records FAIL without the costs. FAIL is cached, so a resumed run does not retry the case.
- `PlainAgent/run_case.py:50` uses budget + 900 s, which is shorter than one quota pause. The read at :64 is uncaught, so the script crashes before it prints anything.

**Fix, recommended shape (from the defence).** Put the cap in one overridable method:
```python
# Isar_Base
def _client_timeout(self):
    return max(self._connection_timeout, self._timeout + 20)
# MinilangAgent_Base
def _client_timeout(self):
    return None  # one reply spans the whole agent run; budget-exempt time is unbounded
```
- :301 uses `timeout=self._client_timeout()`.
- The now-dead `timeout=/connection_timeout=` arguments at :463 are removed.
- `run_case.py` passes `timeout=None`.

This is better than the finding's `None if ... else max(...)`. That variant lets `_timeout` hold None, and `_timeout` also feeds `eval(timeout=self._timeout * 1000)`, so a future call path could crash with a TypeError. With the override, `_timeout` stays a number.

**The author's choice.** Either no client cap for agent runs, which is how these pipelines have run since April, or a generous backstop such as 2 × budget. With the backstop, a run with enough quota pauses is still cut off. This is caller code outside the approved one-file scope, which is why the triage is AUTHOR.

### F2: autocorrode's client cap (600 s) equals its verification server cap (600 000 ms) (blocker, AUTHOR)

**When each clock starts.** The client's clock starts as soon as it begins waiting for the reply. The server's clock starts later, after it has read and parsed the request.

**The server's timer stretches.** I checked this in the Isabelle2025-2 sources. The server's `Timeout.apply` uses the non-physical event timer, and that timer's deadline is pushed back by the whole process's garbage-collection pause time (`event_timer.ML:82`). It is also multiplied by the `timeout_scale` option. The client cap is multiplied by neither.

**Consequences.** On a shared verification server, the client always gives up first:
- A verification that reaches its server cap no longer fails just that one case. It closes the worker's only client.
- A verification that finishes between 600 s and 600 s plus the GC time is cut off, and its real verdict, possibly SUCCESS, is lost.

After the close, every later case on that worker still runs the paid agent. Because `_snapshot_goals` and `_verify_via_repl` swallow every error, each of those cases is then recorded as a cached FAIL. The pairing of 600 s and 600 000 ms was set on 2026-05-27 and 2026-06-01, while the client cap could not fire, so it has never run with a live cap.

**Fix.** Keep one value and derive both caps from it, for example `VERIFY_TIMEOUT_S = 600`, used as `eval(..., timeout=VERIFY_TIMEOUT_S * 1000, ...)` and as `REPLClient(..., timeout=2 * VERIFY_TIMEOUT_S)`. The margin must be generous, because GC time and `timeout_scale` both stretch the server's cap.

**Parts of the finding I reject as out of scope for F2:**
- Making autocorrode reconnect inside its own methods. Once the client cap is above the server cap, a client timeout means the server is stuck, and the harness question belongs to F3.
- Adding a sentence to the constructor docstring. It is not needed to fix this bug.

### F3: the consequence the author accepted is described wrongly (major, AUTHOR)

**What the brief says.** "The evaluation harness does not reconnect, so after one timeout the remaining cases on that client fail."

**What the code does.** I checked this against `evaluator.py:1011-1094` and the `start_case` mixins, and the defender ran it end to end on the real code.

1. **With pass@1**, the timed-out case is recorded as FAIL and the worker keeps the closed client. The next case, which did nothing wrong, fails in `rollback('init')` → `_chk_live` → REPLFail → CaseNotAvailable. It is recorded as CASE_NOT_AVAILABLE without being attempted. Only then does the worker reconnect. CASE_NOT_AVAILABLE is not cached, so a resumed run retries that case.
2. **With pass@N**, which the fleet uses (`run_eval.py`: `[args.driver] * args.pass_num`), the `rollback('EVAL')` before the next attempt sits outside the `try`. The REPLFail escapes `validate`, and the timed-out case itself becomes CASE_NOT_AVAILABLE. The errors, costs and log_ids of its earlier attempts are lost, and a resumed run pays for all the attempts again.
3. **The whole run can then hang forever. This bug already existed.** The REPLFail branch breaks (:1063, and likewise :1048 for revalidate) before the statistics block, so `remaining_cases` is never decremented. Once the queue is empty, the worker sleeps and retries forever.
4. **autocorrode** matches the brief's sentence, but only there. The failures are silent apart from a warning, each one still pays for an agent run, and each is recorded as a cached FAIL.

**Fix.**
- **Required:** give the author these four points and ask them to confirm the acceptance again. The ruling itself stays: closing the client is still better than silently pairing later requests with the wrong replies.
- **Recommended for the author** (both are in `evaluation/`, outside the diff):
  - (i) Delete the two `break`s at :1048 and :1063. The REPLFail branch then falls through to the statistics update and to the existing `if result.status == CASE_NOT_AVAILABLE: break`. This fixes the hang for every REPLFail and only deletes lines.
  - (ii) Add `break` after `errors.append(E)` in the attempt loops' `except TimeoutError` handlers. The client is closed, so no later attempt can succeed, and `validate` then returns FAIL with the data it already has.
- **Optional, needs a public-API decision:** (iii) a public `closed` property on Client, which `_chk_live` and `_write` would reuse since both repeat that test today, plus an Evaluator hook that lets `eval_server` reconnect before the next case.
- **Rejected:** the variant that checks whether `errors` contains a TimeoutError. autocorrode turns its TimeoutError into a string, so the check would miss it.
- Correct the brief if it is reused. The record never made this claim, so it needs no correction here.

### F4: a timeout abandons the server-side request instead of stopping it (minor on its own, major while F1 is unfixed; AUTHOR)

**Facts, all verified.**
- Before the migration, `close()` also called `Client.kill_client(self.addr, self.client_id)` (seen in `c23aee2^`).
- The server's kill handler calls `Isabelle_Thread.interrupt_thread` on that client's worker thread.
- The server's per-client `loop` checks for end-of-stream only between requests, so it does not notice a closed client during a request.
- Nothing calls `kill_client` any more.

**Consequence.** After a timeout, the harness reconnects and starts the next case on the same server while the abandoned request keeps running. Each timeout therefore adds one job above the configured parallelism. On the agent path, that job also spends LLM tokens that are never recorded. Before the migration, the evaluator's own timeout path went through `__aexit__` → `close()` → kill, so this orphaned work was stopped. The ruling says "restore the pre-migration semantics", and that part is not restored. After the F1 and F2 fixes this becomes rare, which is why it is rated minor.

**Fix** (in the timeout branch only):
```python
except TimeoutError:
    self.close()
    if self.client_id is not None:  # a handshake timeout has no id yet
        with contextlib.suppress(Exception):
            await Client.kill_client(self.addr, self.client_id)
    raise
```
- Rejected placements: the synchronous `close()` (it would need blocking I/O or a fire-and-forget task) and every `__aexit__` (the kill would also fire when the server thread is idle).
- The trade-off for the author: one extra connection, and up to about 60 s + 60 s of delay on a server that has stopped responding.
- If F5 is also adopted, keep the kill on the client's own timeout only. Doing network I/O while the task is being cancelled is wrong.
- The drafter shapes the combined handler and it goes back to review.

### F5: only the client's own timer closes the client (minor, AUTHOR, recommend adopting)

**Reproduced by four reviewers and the defender.** Suppose a caller bounds a call itself with `asyncio.wait_for(client.eval(...), t)` or `async with asyncio.timeout(t)`. The caller then receives the same `TimeoutError` class as for the client's own timeout, but the client is left open, and its next call silently returns the previous reply. `task.cancel()` has the same effect. The docstring's own reason, "the stream is then out of step", applies to all of these, but the code enforces it for only one of them. No current caller does this, so this is a way the shape invites a future mistake rather than a live failure.

**Fix.** Change `except TimeoutError:` to `except BaseException:` at `IsaREPL.py:179`, and reword the docstring to "a read that does not finish closes the client, as the stream is then out of step". REPLFail from `_parse_control_` is raised outside this method, after a complete reply has been read, so it is unaffected.

**Sub-claims I reject:**
- A reset from the other end and msgpack BufferFull both fail loudly, not silently.
- The remark about `_write`/`drain()` is wrong: a cancelled drain loses no bytes. No guard is needed there.

**Why AUTHOR.** It widens the trigger of a ruled mechanism from "timeout" to "any read that does not finish", and it rewords a docstring that about 15 external call sites rely on.

### F6: client caps at or below the server timeouts in tests (minor, DRAFTER_THEN_REREVIEW)

**Only one sub-claim stands.** `Semantic_Embedding/Test/test_resolve_notation_e2e.py:140` uses a cap of 120 s, but its eval has a deliberate 300 s budget (its own RPC budgets add up to about 270 s). So a slow but valid run of 120-300 s now crashes where it used to pass.

**Fix.** Raise that cap to 360 (server budget plus a margin), not None. Optionally raise test_desugar's cap to 180, only so that the server's own timeout message is what gets reported. If the author wants a docstring clause such as "keep it above any timeout passed to eval/file", that wording is user-visible and is the author's.

### F8: corrections to the record (minor, DRAFTER_THEN_REREVIEW)

**What holds:**
- (b) The probe exists only in the session scratchpad, on tmpfs that gets archived and cleared, and the record cites no path. The record also says the negative control ran "on the same probe", but it was actually a separate heredoc with a 5 s sleep, while the probe file sleeps 8 s. I confirmed both in the transcript.
- The record lists `IsaMini/REPL.py` as a caller, but that module never builds a client (see §6).
- **A process violation:** the Resolution section was added by a Python script (transcript line 4956, `s.replace(...)` plus `s += ...`). The project rule "No scripted edits to plan documents" covers this record ("and the like").

**Fix, by hand, no script:**
- Copy the probe and the negative-control snippet into `contrib/Isa-REPL/ai-artifacts/`, left uncommitted as the experiment-script rule requires, and cite the paths.
- State the two runs truthfully.
- Strike or annotate `IsaMini/REPL.py` in the caller list.
- Update "the three connects" if F9 lands.
- Record how F1-F5 were decided.

**What I reject:** (a) the claim that "written against the old meaning" is false, since the next sentence of the record already says none of the handlers could fire; and (c) the Python version floor, since F7 is rejected.

### F9: `test_server` and `kill_client` still duplicate the whole one-shot exchange (minor, DRAFTER_THEN_REREVIEW)

**The duplication.** The two methods are identical statement for statement, apart from the message and the `return`. The diff made the same two edits in both.

**Why it matters.** The regression under review has this exact shape: the migration dropped the bound separately in each copy. Merging them turns "remember to change both copies" into something the code enforces, which is the project's elegance criterion, and it follows the rule against copy-paste-and-modify. It extends the ruled `_read_object` helper and does not reverse it.

**Fix.** One private classmethod that sends one message on a new connection. It reuses `_parse_address` and `_read_object`, and `test_server` and `kill_client` become one-line wrappers with unchanged names and signatures (sketch in the defence; `_request_once` is private and not user-visible). Do not add a `_connect` helper. Update the record's "three connects" sentence.

## 3. Rejected

- **F7 (Python 3.10 `asyncio.TimeoutError`): rejected.** The failure it describes cannot happen. `import IsaREPL` pulls in `Isabelle_RPC_Host.universal_key`, which contains `type universal_key = bytes`, Python 3.12 syntax. So the module cannot even be imported on 3.10 or 3.11. The proposed `>=3.11` floor would also be the wrong number.
- **F6 sub-claims:** test_desugar (only the error message changes), mathbench_repl (it retries until a deadline, and its probe is a trivial theory), test_position_context (a guess with no runtime evidence), and evaluator.py's margin of `+20` (no failure named; the default cap there is actually max(1200, 520) = 1200). All nitpicking.
- **F6's loosening proposal:** see §4.
- **F5 sub-claims** about a reset from the other end, BufferFull and `_write`: these fail loudly, and drain() loses no bytes.
- **F2 parts (2) and (3)**, and **F8 parts (a) and (c)**: as explained above.

## 4. Loosening proposals

1. **Relax the one-file scope so the caller fixes land together with the Client fix: recommended.** The brief treats this as a one-file change. The only safe way to land it is together with the F1 and F2 caller edits, which are in `evaluation/` (main repo), in the Isa-Mini submodule (PlainAgent/run_case.py) and in the Semantic_Embedding test. Gain: the restored cap never goes live with values that have never been tested. The author has to approve the wider scope.
2. **A per-read timeout keyword on `_feed_and_unpack` (from F1): not recommended.** It would let only the agent-reply reads pass None. The `_client_timeout()` override solves F1 without relaxing anything, and the only gain would be a cap on the agent clients' setup calls, which have had no cap since April with no reported hang.
3. **Make the reply wait depend on the server timeout, i.e. `max(self.timeout, server_timeout + ALLOWANCE)` in eval/file (from F2 and F6): not recommended.**
   - It cannot enforce the invariant it promises. `hammer` sends its budget in seconds, `cmd_timeout` bounds each command rather than the whole eval, and `run_app` and the raw `_write` + `_feed_and_unpack` exchanges carry no budget at all.
   - The server's cap stretches with GC pauses and is multiplied by `timeout_scale`, so ALLOWANCE would be a magic guess.
   - It needs special handling for None (`max(None, x)` raises TypeError), and it reverses the ruled pre-migration semantics of an independent cap.
   - Deriving both values from one constant in the caller, as proposed for F2, gets the invariant where it matters without any of this.
4. **The curator's merge of 2 and 3 into one parameter where None means "no bound": not recommended.** It gives one parameter three meanings (0, a number, None) and carries the weaknesses of both proposals.

## 5. Curator deletions: all endorsed

- **Write bound (nit).** The docstring only promises a bound on the connection and on replies. A request would have to be bigger than the kernel socket buffers (several MB) and be sent to a server that has stopped responding before drain() blocks. No realistic case.
- **Stale `Client.create()` sentence.** The drafter already raises it with the author, and it was not introduced by this change.
- **No regression test.** No wrong outcome is named, Isa-REPL has no test harness, and experiment scripts are not committed by rule.
- **AoA/test.py's 1200 s cap.** I confirmed that `run_all_tests` defaults to `mode="test"` and that `test_AoA.py` calls it that way. That mode makes no LLM calls, so the 14 400 s budget never applies, and the cap has been live since before the migration.

## 6. Separate items for the author (existing bugs, not conditions)

- **`contrib/Isa-Mini/IsaMini/REPL.py`.** Line 1 is `import IsaREPL as REPL`, and `class REPL:` on line 3 rebinds the same name. So every `REPL.Client(...)` / `REPL.VERSION` inside the class raises AttributeError, and evaluator.py's MiniREPL (MiniLang_*) evaluators cannot work today. Related: once the module works, its `close()` does a `\close` request/reply on a client that may already be closed. That raises REPLFail, which replaces the TimeoutError or CancelledError the caller should see.
- **The run that never ends** (F3 point 3): the REPLFail branches at `evaluator.py:1048/1063` skip the `remaining_cases` decrement.
- **Python-version metadata** (from the F7 defence, low priority):
  - Isabelle_RPC declares `>=3.10`, but its code needs 3.12.
  - The Isa-Mini conda recipe declares `>=3.11`.
  - IsaREPL's pyproject does not list isabelle-rpc as a dependency.

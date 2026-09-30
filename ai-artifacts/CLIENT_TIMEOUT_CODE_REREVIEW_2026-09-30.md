<!-- Judge report of the second adversarial review round (workflow wf_2eee2be5-fcb, 12 agents, claude-opus-5-5 at xhigh, 2026-09-30), after the author's rulings on F1-F5.  Verdict MET_ON_CONDITION; the conditions are questions for the author (the kill timeout value, F6, G2) and record corrections (G3, G4) plus one comment (G5), all handled in the conversation of 2026-09-30. -->

# Round-2 judge report: restoring the client-side timeout of `IsaREPL.Client` (2026-09-30)

## 1. Verdict: MET_ON_CONDITION

**Summary.** The round-2 code does what the author's five rulings ask, with one exception. F4's timeout value for the kill was never chosen by the author, and the code quietly uses 60 s. What remains is paperwork and questions for the author, not code defects:
- one number the author must choose;
- one test edit the author must approve or decline;
- hand corrections to the record;
- an honest status report to the author.

No third review round is needed. The only code changes left are one number (G1), a three-line message fix if the author wants it (G2), and one comment (G5). All three were checked with scripts that simulate the relevant behaviour, so no REPL server was needed.

**What was checked.**
- `IsaREPL.py` (Client class, lines 158-236), `evaluation/evaluator.py` (Isar_Base, MinilangAgent_Base, evaluate_and_save), `evaluation/plain_agent.py`, `evaluation/autocorrode.py` and `contrib/Isa-Mini/PlainAgent/run_case.py`, all against the brief's round-2 diffs.
- The author's rulings in the transcript (records 5163, 5166, 5217 and 5221) and the status report (record 5415).
- Two scripts of my own on .venv Python 3.12.3, in `scratchpad/judge2/`:
  - `msg.py`: a socket timeout says `'timed out'`, while `asyncio.wait_for` gives an empty message.
  - `inner.py`: an `except TimeoutError` inside the read catches only the client's own timer. A caller-side `asyncio.timeout`, a caller-side `wait_for` and `task.cancel()` all pass through it untouched.

### Status of the round-1 conditions

**C1 (F1): MET.**
- `MinilangAgent_Base._client_timeout()` returns None. `PlainAgent_Base` inherits it, and `run_case.py` passes `timeout=None`.
- Isar evaluators keep `max(connection_timeout, timeout + 20)`, the formula that was already live before the asyncio migration.
- The requirement that these fixes land "in the same change" can only be checked at commit time; see §7.

**C2 (F2): MET.**
- One constant, `VERIFY_TIMEOUT_S = 600`, gives both the client cap (1200 s) and the server cap of the verification eval (600 000 ms).
- The comment above it promises too much; that is G5, a nit.

**C3 (F3): MET.**
- The author saw the corrected facts before ruling. Record 5163 lists pass@1, pass@N and the endless-run bug, and the author answered "F3 接受全部建议" ("accept all suggestions").
- Item (i): both `break`s in the worker loop are deleted.
- Item (ii): all four attempt loops `break` after a TimeoutError.
- Item (iii) was never shown to the author. So "all suggestions" did not cover it, and leaving it undone is correct. It is still an open question for the author (see condition A4).

**C4 (F4, F5): PENDING_AUTHOR.**
- F5 is met: any read that does not finish closes the client. Every interrogator reproduced this.
- F4 is placed as ruled: the kill is sent only on the client's own timeout, only when a client id exists, and inside `suppress(Exception)`.
- But the suggestion the author accepted said the kill's timeout "应传一个小值而不是默认 60 秒，具体多少请你定" ("should be a small value, not the default 60 s; how much is for you to decide"). The author gave no number, and the code uses the default 60 s (G1).

**C5 (F6, F8, F9): NOT_MET.**
- F9 is met: `_request_once` reuses `_parse_address` and `_read_object`, and the record no longer says "three connects".
- F8 is only partly met. The record wrongly claims every broken caller was fixed (G3). It attaches the author's quote to F9, leaves out how F1 was decided and the F3 consequence that remains, and cites the harness simulation by no path (G4).
- F6 is not done. It waits for the author's approval to touch Semantic_Embedding, which is round-1 loosening proposal 1, still unanswered.

### Conditions for acceptance

- **A1 (G1, C4).** Ask the author for the kill's timeout value and apply the answer. Keeping 60 s is an acceptable answer: it is exactly the pre-migration behaviour. What matters is that the author is asked.
- **A2 (F6, C5).** The author either approves `test_resolve_notation_e2e.py:140` `timeout=120` → `timeout=360`, landed with the Client change, or declines it. If the author declines, the record names F6 as a known open exception (G3).
- **A3 (G3, G4, C5).** The drafter edits the record's Resolution section by hand, no script, as specified below. The drafter also copies the harness simulation into `contrib/Isa-REPL/ai-artifacts/` (not committed) and cites it.
- **A4.** Before asking for commit approval, the drafter sends the author a corrected status report. It must replace "五条裁定已全部落实" ("all five rulings implemented") and list every open item, each explained from scratch:
  1. the kill timeout value;
  2. F6 and the Semantic_Embedding scope;
  3. G2's message text;
  4. F3 item (iii), which the author has never seen;
  5. the stale `Client.create()` docstring sentence, raised at record 4972 and never answered.

  It must also state two facts plainly:
  - `evaluator.py:468` removed the budget override by forwarding the constructor's arguments rather than deleting them (see G6).
  - `evaluation/plain_agent.py` and `PlainAgent/run_case.py` are untracked, so the commit cannot carry their edits.

**Not blocking.**
- G2: the author decides; either answer is acceptable.
- G5: the drafter fixes the comment.

## 2. Accepted findings

### G1: the kill uses the default 60 s, although the suggestion the author accepted asked the author to pick a small value (minor; AUTHOR; blocking as A1)

**What is wrong.** The code departs from the text the author accepted, and the drafter reported the work as complete.

**Evidence.**
- In record 5163 the drafter wrote, on F4: "`kill_client` 的那个超时应传一个小值而不是默认 60 秒，具体多少请你定" ("the kill_client timeout should be a small value rather than the default 60 s; how much is for you to decide").
- The plan in the same record lists "F4（含 kill 的超时值）" ("F4, including the kill's timeout value") as a decision for the author.
- The author answered "F4 接受建议" ("F4: accept the suggestion", record 5221) and gave no number. There is no user turn after 5221.
- `IsaREPL.py:185` calls `await Client.kill_client(self.addr, self.client_id)`, so the kill uses the default `timeout=60` defined at `:234`.
- The status report (5415) says every ruling was implemented. The brief says "nothing else pending" and describes the 60 s default without flagging it as a departure.

**Consequence.** On a server that has stopped responding, the caller's TimeoutError arrives about 60 s after the cap (the defence measured 61.1 s with a 1 s cap). If the connect also stalls, it can arrive up to about 120 s late.

**Severity.** Minor in runtime terms, which is why I lower it from major. It is still a blocking condition, because the project rule "Never Act on Assumptions — ALWAYS Ask" means an open question to the author cannot be closed silently.

**Fix.** Put the question to the author with these facts:
- The kill's reply is thrown away.
- The server interrupts the client's thread and replies immediately, without waiting for it (Server.ML:284-300).
- A small value, such as 2 s, still delivers the kill to a local server whose accept loop is merely slow. The defence measured this.
- A small value can lose the kill only on a remote server whose connect takes longer than that value.
- 60 s is exactly what the pre-migration `close()` used.

If the author chooses N, the code becomes `await Client.kill_client(self.addr, self.client_id, N)`; nothing else changes. Record the value in the record's Resolution section, and correct the brief's F4 description and its "Not done" list.

### G2: the client's own timeout now raises TimeoutError with an empty message where the pre-migration client said "timed out" (minor; AUTHOR)

**What is wrong.** Ruling 1 says to restore the pre-migration behaviour. The exception class was restored, but the message was not.

**Evidence.**
- I measured it on .venv 3.12.3. A socket timeout gives `TimeoutError('timed out')`; `asyncio.wait_for` gives `TimeoutError()`, whose `str()` is empty.
- `evaluation/failure_analysis.py:34-36` puts timeouts in its Timeout category through the pattern `r'^timed out'`. That pattern was added in 5de8abe6 (2025-04), when client socket timeouts were live, and no pattern in its table matches an empty string.
- `tasks/Baldur/failure.py` still calls `analyze_failure` on Isar and MiniLang result databases.

**Concrete case.** An Isar evaluation whose reply is later than the 1200 s cap is stored as FAIL with `[TimeoutError()]`. Three things then go wrong:
- its CSV "error" cell (`evaluator.py:992`) is empty;
- `failure_analysis` counts it as "Unknown" and prints "Unknown failure: " with nothing after it;
- autocorrode's snapshot path records "Snapshot error: " with nothing after it.

**Fix (recommended, read site only).** In `Client._read_object`:
```python
            except mp.OutOfData:
                try:
                    data = await asyncio.wait_for(reader.read(65536), timeout)
                except TimeoutError:
                    raise TimeoutError("timed out") from None  # the socket-era text; evaluation/failure_analysis.py matches it
```
- This one edit covers every reply wait: the client's own reads, `test_server` and `kill_client`.
- The class is unchanged, so every `except TimeoutError` and the kill test in `_feed_and_unpack` keep working.
- My `inner.py` confirms that caller-side timeouts and cancels still pass through untouched, with an empty message or as CancelledError. As a side benefit, the client's own timeout can now be told apart from a timeout the caller imposed.
- `from None` also removes the noisy OutOfData/CancelledError chain from tracebacks.

**Optional, for the author.** The two connect waits could get the same message. But the translation must then skip the kernel's own connect timeout, which Linux raises as a TimeoutError carrying errno 110 and the address, so that information is not thrown away. A guard such as `if e.args: raise` does that. The only reader of a connect timeout is one log line in the worker loop, so the read-site fix alone is enough.

**Why AUTHOR.** The literal is CPython's own text, so nothing new is worded. But it appears in CSV cells and in logs, which makes it user-visible text, and in this project the author approves such text.

### G3: the record says every caller broken by the restored cap was fixed, but F6 is still open (minor; DRAFTER_NO_REREVIEW)

**Evidence.**
- Record line 92 says "The callers that the restored cap would have broken were fixed with it (the review's F1–F3 …)".
- Record line 47 names "the Semantic_Embedding tests" among the callers, so a reader would take that test as fixed too.
- `contrib/Semantic_Embedding/Test/test_resolve_notation_e2e.py` is unmodified on disk. Line 140 sets `timeout=120` and line 142 calls `eval(ML_TEST, timeout=300_000)`.
- The record is the only one of these artifacts tracked in git (02dc15e). If the change lands as it stands, the durable record states something false.

**Consequence.** Once the cap is live, a valid run of that test lasting 120-300 s crashes with a TimeoutError, and its request is killed.

**Where the finding goes too far.** Two parts of it I reject:
- The title's "resolved" can stay. The record is about the constructor timeout that was stored but never read, and about the echo defect; both are resolved.
- The wording is not the reason C5 fails. C5 fails because the F6 edit has not landed.

**Fix, by hand.** In the Resolution paragraph at line 92, after "(the review's F1–F3, rulings of 2026-09-30)", add the one exception:

> with one exception, still open: `contrib/Semantic_Embedding/Test/test_resolve_notation_e2e.py:140` builds its client with a 120 s cap around an `eval` whose server-side budget is 300 s (line 142), so a valid run of 120-300 s now raises `TimeoutError` (review F6). The proposed edit `timeout=120` → `timeout=360` awaits the author's approval to touch Semantic_Embedding.

If the author approves F6 before the change lands, apply the test edit together with the Client change. Then cite F6 among the fixes instead of naming it as an exception.

### G4: the record misattributes the author's "接受建议" to F9, leaves out how F1 was decided and the F3 consequence that remains, and cites the harness simulation by no path (minor; DRAFTER_NO_REREVIEW)

The round-1 F8 fix asked the record to state truthfully how F1-F5 were decided. I checked each part against the transcript and the disk.

- **(a) Confirmed.** Record lines 57-58 say "extended by the review's F4, F5 and F9 the same day, '接受建议'". F9 was presented as something the drafter would fix itself (record 5163, section 二), and the author ruled on F1-F5 only.
  - This matters because in this project an author ruling binds every later review. The misattribution would therefore shield the drafter's `_request_once` shape from future review.
- **(b) Confirmed, low.** The record says agent runs pass no cap. It does not say that the author first asked for a cap of budget + 5 min (record 5166), weighed budget + 30 min against 2 × budget, and then chose no cap (record 5221).
  - The record is the durable artifact, so without that sentence someone may propose a cap again without knowing the author already rejected it.
  - The accepted F3 consequence that remains is real: after a client timeout on an Isar evaluator, the next case is recorded CASE_NOT_AVAILABLE without being attempted. It no longer happens on the agent path, so the sentence must name the Isar evaluators.
- **(c) Nit, fold it into the same edit.**
  - Where the record puts the 14 425 s run, it reads as a consequence of quota pauses, but that run had none (quota_wait_time 0.0).
  - Its overrun came from the budget being checked by polling rather than enforced exactly.
- **(d) Confirmed.** "Reproduced with a fake evaluator before and after the fix" cites no path. `harness_sim.py` exists only in the session scratchpad, on the tmpfs that gets archived and cleared.
  - The "before" leg was run against the harness at HEAD. HEAD will stop pointing at that version once the change is committed. The last commit of `evaluation/evaluator.py` is 2dbb65a4.

**Fix, by hand, no script.**
1. **Lines 57-58.** Change the parenthetical to: (ruled 2026-09-30, "赞同你的建议"; extended the same day by the review's F4 and F5, "接受建议", and by its F9, the merge of the one-shot exchange, which the drafter made at the review's recommendation without a separate ruling).
2. **Lines 92-97.** Quote the three rulings: F1 "好的，那么就不给超时了", F2 "可以改", F3 "接受全部建议". After "now pass no cap", add that the author chose this over a backstop of budget + 30 min or 2 × budget. Reword the 14 425 s clause so it says that even without a quota pause the budget, checked by polling, overran: 14 425 s with no quota wait, against a would-be cap of 14 420 s.
3. **After the worker-loop sentence**, add: "One accepted consequence remains: after a client timeout on an Isar evaluator the worker still holds the closed client, so the next case is recorded CASE_NOT_AVAILABLE without being attempted (not reused from the result DB, so a resumed run retries it) before the worker reconnects. Reconnecting first is the review's F3 item (iii), not done."
4. **The simulation.** Copy `scratchpad/harness_sim.py` to `contrib/Isa-REPL/ai-artifacts/client_timeout_harness_sim.py`, leave it uncommitted, and cite it. Give the two results:
   - with the edited harness, {c1: CASE_NOT_AVAILABLE, c2: SUCCESS, c3: SUCCESS};
   - with `git show 2dbb65a4:evaluation/evaluator.py`, the run hangs past 20 s.

   An argument that selects the evaluator source is optional; a sentence saying how the "before" leg was run is enough.

**Rejected sub-claim.** The claim that the kill "can never fire on the agent path" is rightly deleted. `AoA/test.py` `run_all_tests` (line 18391) still builds its client with `timeout=1200` around agent invocations.

### G5: the autocorrode comment says the server's verdict "always" arrives first, which stops holding once timeout_scale reaches about 2 (nit; DRAFTER_NO_REREVIEW)

**Evidence.**
- `Server.ML:614` applies the eval cap through `Timeout.apply`.
- In `timeout.ML:28-29` and `:42`, that cap is multiplied by `timeout_scale`, and the timer starts after the server has read the request.
- The client's cap is a fixed 2 × 600 s. So from a `timeout_scale` of about 2 upwards, the client gives up first. The defence measured this already at 1.98.
- The F2 failure then returns: the worker's only client is closed, and every later case on that worker is recorded as a cached FAIL.
- `PLAN_P0_COMMON.md` D60 tells users of slow machines to set exactly this option.

**Why it is a nit and not nothing.** The comment names `timeout_scale` as something that stretches the server's timer and in the same breath promises "always". A maintainer on a slow machine would be told the one wrong thing: that the client cannot be the side that gave up. Only the wording is at issue; the 2× margin itself was ruled.

**Fix (comment only)** at `evaluation/autocorrode.py:103-105`:
```python
    # Server-side cap of the verification eval, in seconds. The client waits
    # twice as long so that the server's verdict arrives first (its timer
    # starts later and stretches with GC pauses and timeout_scale); at a
    # timeout_scale of about 2 or more the client gives up first.
```

## 3. Rejected

- **G6 (MinilangAgent_Base forwards `timeout`/`connection_timeout` instead of deleting them): rejected. It names no wrong outcome.**
  - Nothing on the agent path reads either field, so runtime behaviour is identical.
  - The agent command-line flags `--timeout` and `--connection-timeout` were already ignored at HEAD, since commit 018f8935 (2026-05-10). The finding's own code fix would not change that.
  - Deleting the two arguments literally would leave `_timeout = 500` after `timeout=900` was passed, so the object's fields would contradict its arguments. Forwarding keeps them consistent.
  - The one useful residue, telling the author that the implementation differs from the text shown, is folded into condition A4.
  - Deleting the dead command-line flags is a separate, pre-existing item for the author.
- **Interrogator observations the curator did not raise: rejected as nits or already ruled.**
  - A kernel ETIMEDOUT also triggers the kill. This is harmless.
  - A cancel while `_write` is waiting in `drain()` was already rejected in round 1.
  - Three docstring points: "each reply" versus "each chunk" (the server packs a whole reply at once); the kill delay not being mentioned; `_request_once` saying "its reply".
  - `MiniLang_Base` still writes the cap formula inline, but that path cannot run today.
  - Under pass@N, `success_rate.py` infers the number of attempts from the length of `errors`, and after the `break` a FAIL can carry fewer than N errors. This only matters in a contrived case.

## 4. Loosening proposals

1. **Recommended: re-forward round-1 loosening proposal 1 for F6 alone.** It would relax the one-module scope so the Semantic_Embedding test edit (120 → 360) lands with the Client change. The gain is that the restored cap never goes live against the one known in-repository caller whose cap is below its own eval budget. The author never answered this proposal.
2. **Not recommended now: a cap on the agent clients' connect and handshake only.** It would relax the F1 ruling ("no cap") for setup calls only. The gain is that reconnecting to a server that accepts connections but never answers would fail instead of hanging forever. Nothing indicates such a hang today, and without the cap the behaviour is no worse than before this change. Revisit it only if the server-side lead in §6 is confirmed.
3. **Not recommended: also send the kill on a caller-side cancel, as a detached task.** `asyncio.run` cancels detached tasks at shutdown, and a future caller can already call `Client.kill_client` itself.

## 5. Curator deletions: all endorsed

- **The kill "can never fire on the agent path".** Deleted rightly: `AoA/test.py:18391` still uses `timeout=1200` around agent invocations, and a mode other than "test" runs a real driver.
- **`plain_agent.py` exists on disk only.** Deleted rightly as a finding: `git ls-files` finds nothing, `.gitignore:27` ignores `/evaluation`, and the only importer is another agent's uncommitted `evaluator_top.py`, so no committed code path lacks the break. The disclosure goes into A4.
- **The eight merges** into G3, G4, G5 and G6 are correct duplicates.

## 6. Separate items for the author (not conditions)

- **Unverified server-side lead, older than this change.** The accept loop reads the first message of every new connection inside the accept thread (`Server.ML:272-274`) and handles only the CONTINUE exception (`:840`), while mlmsgpack raises Unpack at end of stream. So a connection that opens and closes without sending anything, like `tcp_ok` in `tools/aoa_putnam_eval/run_fleet_eval.sh:80`, may end the accept thread. Someone allowed to run a throwaway server should test it.
- **Dead agent command-line flags.** `--timeout` and `--connection-timeout` in the agent handler of `evaluator_top.py` are accepted and ignored, as they already were at HEAD. Removing them is a user-visible change and the author's decision.

## 7. Commit-time notes

- The main-repository commit must carry `evaluation/evaluator.py`, `evaluation/autocorrode.py` and the Isa-REPL submodule bump together. That is how C1 and C2's "lands in the same change" is satisfied.
- `PlainAgent/run_case.py` (untracked in Isa-Mini) and `evaluation/plain_agent.py` (git-ignored) cannot be committed; their edits stay on disk only.
- `evaluator.py` carries another agent's uncommitted `enable_read_memory` edit, which changes the default of experience retrieval for agent evaluations to off. Per CLAUDE.md it will be swept into the commit, and the commit message must describe it.
- The experiment scripts in `ai-artifacts/` stay uncommitted.
- The commit needs the author's approval.
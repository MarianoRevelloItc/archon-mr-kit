---
name: debugging-and-error-recovery
description: Use when investigating a bug report, a CI failure, an exception in production, or when a workflow run fails for non-obvious reasons. Triggers on stack traces, "broken", "doesn't work", "intermittent", "flaky", red CI badges, post-mortem requests, or "what went wrong?" / "why is this failing?" questions.
---

# Debugging and Error Recovery

A systematic 5-step triage. The goal is **localize before you fix** — a fix without a confirmed reproduction is a guess, and guesses break things.

---

## The 5 steps

### Step 1: REPRODUCE

A bug you can't reproduce is a bug you can't fix. First task: get a deterministic reproduction.

**Commands:**

```bash
# Read the failing run / report end-to-end before touching anything.
gh run view <id> --log         # CI failure
gh issue view <num>            # bug report
tail -n 200 path/to/error.log  # prod exception
```

**Capture environment:**

```bash
git rev-parse HEAD              # what commit are we on?
git status                      # any local diffs?
python --version                # interpreter version
pip freeze | grep <suspect>     # dep version
```

**Try to reproduce locally.** If it's intermittent:
- Run the failing test 100×: `pytest tests/test_x.py::test_y --count=100` (with `pytest-repeat`).
- Check ordering: `pytest --random-order` — does test order matter?
- Check timing: are there `sleep`s, real network calls, real time-of-day logic?

If you cannot reproduce, **stop and gather more info** before guessing a fix. Ask for: timestamps, request IDs, logs, the exact command run, the exact env vars set.

**Anti-pattern**: "It's probably a race condition" + push a `try/except` band-aid. That's not a fix; it's an information-discarding suppression.

### Step 2: LOCALIZE

Narrow to the smallest scope that contains the bug.

**Git bisect** for "it worked yesterday, broke today":

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-commit>
# bisect checks out a commit; run your repro
bash repro.sh && git bisect good || git bisect bad
# repeat until bisect prints "first bad commit"
git bisect reset
```

**Log greps** for "where does this error come from":

```bash
# Look for the exact error string
git grep -n "RareErrorMessage" -- '*.py' '*.ts'

# Find every catch/throw/raise of this type
git grep -n "raise CustomError\|throw new CustomError" -- '*.py' '*.ts'

# Find recent changes to relevant files
git log -p --since="7 days ago" -- path/to/suspect.py | head -200
```

**Binary search the file**: comment out half, see if the bug persists, repeat. Crude but fast on a 500-line file.

### Step 3: REDUCE

Build the minimal failing case.

A 200-line repro with 8 dependencies isn't useful. Trim:

- **Delete** unrelated steps until removing one more makes the bug disappear.
- **Inline** any helper that obscures what's happening.
- **Hardcode** values that aren't load-bearing.

The reduced repro becomes the failing test in step 4.

```python
# Before (200 lines, hard to share)
def test_full_user_signup_flow():
    db = setup_db_with_fixtures(...)
    user = create_user(...)
    org = create_org(...)
    invite = send_invite(...)
    accept_invite(invite, user)
    # ... 30 more lines
    assert user.email == "expected@x.com"  # FAILS

# After (10 lines, sharable, points at the bug)
def test_invite_email_lowercased_on_accept():
    invite = Invite(email="USER@X.COM")
    accept_invite(invite, User(email="user@x.com"))
    assert invite.email == "user@x.com"  # FAILS — bug is in accept_invite case-handling
```

### Step 4: FIX

Now that you know exactly where the bug is, write the minimum change that makes the reduced test pass.

- **One commit, one fix**. No drive-by refactors.
- **Test first**. Add the reduced repro as a regression test (RED), then make it GREEN.
- **Don't add `try/except`** unless the actual fix is "this exception is expected, swallow it with a log". `try/except: pass` is rarely correct.

If the fix touches a load-bearing pattern across the codebase, scope-creep alarm: revert and open an issue for the broader refactor instead. Bug fixes should be surgical.

### Step 5: GUARD

Prevent regression.

- **Regression test** committed (the test from step 3).
- **Log/metric** added if the bug was hard to spot — emit a structured log when the offending code path runs, so a future regression is grep-detectable.
- **Post-mortem note** if the bug was a recurring class — add to `docs/runbook/INCIDENT.md` or an ADR.

---

## Worked example: a flaky CI test

```
Symptom: tests/test_signup.py::test_email_verified passes locally,
fails on CI ~30% of the time.

Step 1 (REPRODUCE):
  gh run view 12345 --log
  → "AssertionError: expected 'verified=True', got 'verified=False'"
  pytest tests/test_signup.py::test_email_verified --count=50
  → 18 failures of 50. Intermittent confirmed.

Step 2 (LOCALIZE):
  pytest --random-order tests/test_signup.py
  → test_email_verified ALWAYS fails when test_email_unverified ran before it.
  → Test interaction. Probably shared state.
  git grep "verified=True" backend/tests/
  → tests/test_signup.py uses module-level fixture `user`. AHA.

Step 3 (REDUCE):
  def test_a(user): user.verified = False
  def test_b(user): assert user.verified is True  # depends on order
  → Confirmed: shared mutable fixture across tests.

Step 4 (FIX):
  Change `user` fixture from module to function scope.
  pytest --count=50 → 0 failures.

Step 5 (GUARD):
  Add to CI: pytest --random-order (catches future shared-state bugs).
  Commit message references the original CI run: "Fixes flake from run 12345"
```

---

## Anti-patterns

| Anti-pattern | Why it's bad |
|--------------|--------------|
| Adding `try/except: pass` to suppress the symptom | Discards information. Bug still there, just silent. |
| Pushing "fix" without a reduced repro | You're guessing. Often introduces a second bug. |
| Refactoring "while I'm in here" | Inflates the diff, hides the real change, breaks `git bisect`. |
| Skipping the regression test "because it's a one-off" | Bugs you saw once recur. The test is cheap; the recurrence isn't. |
| Trusting a fix because tests pass | Tests pass on the fix you wrote. Run the **failing repro** — does it now pass? |

---

## When the bug is in upstream code

Sometimes the bug is in a dep you don't own.

1. **Confirm with a reduced repro** that calls only the dep's public API.
2. **Search their issue tracker** for the symptom — often someone has reported it.
3. **Pin to a known-good version** as the immediate fix, with a comment linking the upstream issue.
4. **Open an upstream issue / PR** if none exists. Cite the reduced repro.
5. **Don't fork the dep** unless the fix is small and the upstream is dead.

---

## See also

- `tdd` skill — the regression test from step 5 belongs in your TDD loop.
- `documentation-and-adrs` — if the bug exposed a design flaw, write an ADR.
- `docs/runbook/INCIDENT.md` (created by `mr-bootstrap-project`) — production incident playbook.

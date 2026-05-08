---
description: Implement an issue using strict TDD (red → green per behavior). Reads investigation.md or plan.md, writes implementation.md.
argument-hint: (no arguments — reads from workflow artifacts)
---

# MR TDD Implement

**Workflow ID**: $WORKFLOW_ID

---

## Your Mission

Implement the changes specified in the upstream investigation/plan artifact using **strict test-driven development**: one observable behavior per RED → GREEN cycle. Never write code that no failing test demanded.

The `tdd` skill is preloaded — use its red-green-refactor methodology. Do NOT write all tests first ("horizontal slicing"). Do NOT anticipate future tests. Vertical slices only.

**Golden rule**: If you find yourself writing production code without a failing test that requires it, STOP and write the test first.

---

## Phase 0: ORIENT — Detect stack and load artifact

### 0.1 Find input artifact

Read whichever exists (one of these is guaranteed by the upstream `bridge-artifacts` node):

```bash
test -f "$ARTIFACTS_DIR/investigation.md" && echo "BUG_PATH" || echo "FEATURE_PATH"
cat "$ARTIFACTS_DIR/investigation.md" 2>/dev/null || cat "$ARTIFACTS_DIR/plan.md"
```

Extract:
- **Issue number and title**
- **Acceptance criteria** (the "Implementation Plan" steps for bugs, or "Step-by-Step Tasks" / "Acceptance Criteria" for features)
- **Files to CREATE / UPDATE** with line ranges
- **Patterns to mirror** (file:line snippets from existing code)
- **Scope boundaries** ("OUT OF SCOPE" / "NOT Building" — do NOT touch these)

### 0.2 Detect stack scope

Look at the files listed in the artifact and decide which surfaces this change touches:

```bash
# Quick heuristics
HAS_BACKEND="false"
HAS_FRONTEND="false"
grep -qE '^(- |\| )?`?backend/' "$ARTIFACTS_DIR/investigation.md" 2>/dev/null && HAS_BACKEND="true"
grep -qE '^(- |\| )?`?frontend/' "$ARTIFACTS_DIR/investigation.md" 2>/dev/null && HAS_FRONTEND="true"
grep -qE '^(- |\| )?`?backend/' "$ARTIFACTS_DIR/plan.md" 2>/dev/null && HAS_BACKEND="true"
grep -qE '^(- |\| )?`?frontend/' "$ARTIFACTS_DIR/plan.md" 2>/dev/null && HAS_FRONTEND="true"
echo "BACKEND=$HAS_BACKEND FRONTEND=$HAS_FRONTEND"
```

You'll use this to pick the right test command per RED/GREEN cycle.

### 0.3 Read project conventions

```bash
cat CLAUDE.md 2>/dev/null || echo "(no CLAUDE.md)"
cat backend/pyproject.toml 2>/dev/null | head -40
cat frontend/package.json 2>/dev/null | head -40
```

Note Python version, pytest config, eslint rules, vitest config — you'll match these styles exactly.

**PHASE_0_CHECKPOINT:**
- [ ] Source artifact loaded (investigation.md OR plan.md)
- [ ] Acceptance criteria extracted as a numbered list
- [ ] Files to change identified
- [ ] Scope boundaries noted (will NOT touch these)
- [ ] Stack scope detected (backend / frontend / both)
- [ ] Project conventions reviewed

---

## Phase 1: DEPENDENCIES — Install if needed

A worktree may not have local virtualenvs / node_modules. Install only what your scope needs.

### 1.1 Backend deps (if HAS_BACKEND)

```bash
if [ -d backend ] && [ "$HAS_BACKEND" = "true" ]; then
  cd backend
  if [ -d .venv ]; then
    source .venv/bin/activate
  else
    python3.12 -m venv .venv && source .venv/bin/activate
  fi
  pip install -e ".[dev]" --quiet 2>&1 | tail -3
  cd ..
fi
```

### 1.2 Frontend deps (if HAS_FRONTEND)

```bash
if [ -d frontend ] && [ "$HAS_FRONTEND" = "true" ]; then
  cd frontend
  if [ ! -d node_modules ]; then
    npm ci 2>&1 | tail -3
  fi
  cd ..
fi
```

**PHASE_1_CHECKPOINT:**
- [ ] Backend env ready (if needed)
- [ ] Frontend node_modules ready (if needed)

---

## Phase 2: PLAN BEHAVIORS — Decompose AC into observable tests

Take each acceptance criterion from the artifact and break it into **observable behaviors** — the unit at which you can write ONE failing test.

Example: AC "USATCO scores ≥0.5 (has executives + website + PRs)" decomposes into:

| # | Behavior | Test name (sketch) |
|---|----------|--------------------|
| 1 | Score is 0 with no signals | `test_reachability_zero_with_no_signals` |
| 2 | Adding 3 executives adds 0.30 | `test_reachability_adds_030_for_three_execs` |
| 3 | Resolvable website adds 0.15 | `test_reachability_adds_015_for_website` |
| 4 | Recent PR adds 0.15 | `test_reachability_adds_015_for_recent_pr` |
| 5 | Score caps at 1.0 | `test_reachability_caps_at_one` |

Write this decomposition into a scratchpad you'll consult during the loop:

```bash
mkdir -p "$ARTIFACTS_DIR"
cat > "$ARTIFACTS_DIR/.tdd-behaviors.md" <<'EOF'
# Planned Behaviors

| # | AC | Behavior | Test file | Status |
|---|----|----------|-----------|--------|
| 1 | AC-1 | ... | backend/tests/test_x.py | TODO |
| 2 | AC-1 | ... | backend/tests/test_x.py | TODO |
EOF
```

**Rules:**
- Each behavior must be testable through a **public interface** (function call, HTTP endpoint, rendered DOM). Never test private internals — see `mocking.md` from the tdd skill.
- Prefer fewer thicker behaviors over many trivial ones — but each must verify ONE distinct fact.
- If a behavior depends on another, sequence them (test #2 builds on the code from test #1).

**PHASE_2_CHECKPOINT:**
- [ ] Every AC mapped to ≥1 behavior
- [ ] Each behavior has a target test file (existing or new)
- [ ] Behaviors ordered by dependency (foundational first)

---

## Phase 3: TDD LOOP — Implement one behavior at a time

For each row in `.tdd-behaviors.md`, execute strictly:

### 3.1 RED — Write the failing test

1. Open the target test file (create if it doesn't exist, mirroring sibling test files exactly)
2. Add ONE test that exercises the behavior through its public interface
3. Run the test — it MUST fail with a clear error (not a syntax/import error — a true assertion failure or NotImplemented)

**Backend test command:**
```bash
cd backend && source .venv/bin/activate && pytest tests/test_x.py::test_name -xvs
```

**Frontend test command:**
```bash
cd frontend && npm test -- --run tests/x.test.tsx
```

If the test passes immediately or fails for the wrong reason, you wrote a bad test — rewrite it.

### 3.2 GREEN — Minimum code to pass

1. Write the **smallest** change to the production code that makes the test pass
2. Re-run the same test — it MUST pass
3. Run nearby tests to confirm no regression: `pytest tests/test_x.py` or `vitest tests/x.test.tsx`

**Anti-patterns to avoid:**
- Adding configuration, abstractions, or "while we're at it" cleanup
- Implementing future behaviors not yet tested
- Touching files outside the artifact's "Files to CREATE / UPDATE" list

### 3.3 Verify type-check stays clean

After each GREEN:

```bash
# Backend
cd backend && source .venv/bin/activate && ruff check app/ tests/
# Frontend
cd frontend && npx tsc --noEmit && npx eslint --quiet .
```

**Both must exit 0 before you move to the next behavior.** If they fail, fix the type/lint issue NOW — don't accumulate debt.

### 3.4 Update scratchpad

Mark the behavior as DONE in `$ARTIFACTS_DIR/.tdd-behaviors.md` and move on.

### 3.5 Commit cadence

After **each AC** is fully covered (all its behaviors GREEN), make a commit.

Before staging, auto-format changed files to prevent `mr-multi-validate` format drift:

```bash
# Format Python files if any were written/edited in backend/
# Run from repo root (subshell keeps cwd clean even if ruff fails):
(cd backend && source .venv/bin/activate && ruff format <changed .py files>)

# Format TypeScript/TSX files if any were written/edited in frontend/
# NOTE: mr-multi-validate does NOT check frontend format; this is best-effort hygiene only.
# If the project uses biome (biome.json exists in frontend/), run:
#   (cd frontend && bunx biome format --write <changed .tsx/.ts files>)
# Otherwise, check frontend/package.json scripts for the project's formatter and skip if none.
```

Then stage and commit:

```bash
git add -A
git commit -m "$(cat <<'EOF'
test(tdd): AC-N — {behavior summary}

Behaviors covered:
- {behavior 1}
- {behavior 2}

Files:
- {file 1}
- {file 2}
EOF
)"
```

Atomic per-AC commits make `git bisect` and code review trivial.

**PHASE_3_CHECKPOINT:**
- [ ] Every behavior in scratchpad is DONE
- [ ] Every cycle ended GREEN with clean type-check + lint
- [ ] No production code exists that wasn't demanded by a test
- [ ] One commit per AC (or one combined commit for tightly-coupled ACs)

---

## Phase 4: SCOPE GUARD — Verify nothing crept in

Before writing the report, audit the diff for scope creep:

```bash
git diff --stat $BASE_BRANCH..HEAD
git diff $BASE_BRANCH..HEAD -- ':(exclude)*.lock' ':(exclude)package-lock.json' | head -300
```

For every changed file, confirm it appears in the artifact's "Files to change" table OR is a test file directly covering one of the behaviors. **If a file changed and isn't justified by the plan, revert that change.**

**PHASE_4_CHECKPOINT:**
- [ ] Every changed file traces to an AC or its tests
- [ ] No drive-by refactors, no unrelated formatting, no "improvements"
- [ ] No new dependencies added that weren't required by the plan

---

## Phase 5: WRITE — implementation.md

Write `$ARTIFACTS_DIR/implementation.md` so downstream nodes (`mr-multi-validate`, `create-pr`, `synthesize`) can read it:

```markdown
# Implementation Report

**Issue**: #{number}
**Generated**: {ISO timestamp}
**Workflow ID**: $WORKFLOW_ID
**Approach**: TDD (red→green per behavior)

---

## Acceptance Criteria — Coverage

| # | AC | Behaviors | Tests | Status |
|---|----|-----------|-------|--------|
| 1 | {AC text} | {n} | {test names} | ✅ |
| 2 | {AC text} | {n} | {test names} | ✅ |

---

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `backend/app/x.py` | UPDATE | +{N}/-{M} |
| `backend/tests/test_x.py` | CREATE | +{N} |
| `frontend/components/Y.tsx` | UPDATE | +{N}/-{M} |
| `frontend/tests/Y.test.tsx` | CREATE | +{N} |

---

## Commits

{Output of `git log --oneline $BASE_BRANCH..HEAD`}

---

## Deviations from Plan

{If none: "Implementation matched the artifact exactly."}
{If any: list them with reason}

---

## Validation Snapshot (informational — full validation runs in next step)

| Check | Result |
|-------|--------|
| Backend ruff | ✅ |
| Backend pytest (touched files) | ✅ ({N} tests) |
| Frontend tsc | ✅ |
| Frontend vitest (touched files) | ✅ ({N} tests) |
```

**PHASE_5_CHECKPOINT:**
- [ ] `$ARTIFACTS_DIR/implementation.md` written
- [ ] All ACs accounted for in the coverage table
- [ ] All commits listed

---

## Phase 6: REPORT — Output to user (kept brief)

```markdown
## TDD Implementation Complete

**Issue**: #{number} — {title}
**Branch**: `{branch}`

### Coverage
- ACs: {n}/{n}
- Behaviors tested: {N}
- Commits: {M}

### Files Changed
{files-changed table}

### Next Step
Multi-layer validation runs next.
```

---

## Edge Cases

### Test won't fail (false RED)
You wrote a test the existing code already satisfies. Either: (a) the AC is already implemented — mark DONE and skip; or (b) your test isn't actually exercising the behavior. Rewrite it.

### Test fails for wrong reason
Import error, syntax error, fixture missing. Fix the test infrastructure, then re-run. The failure must be the assertion you intended.

### Behavior requires tooling changes (new lib, config)
If the artifact authorized it (listed in dependencies), install/configure it. If not, STOP and add a deviation note — do NOT silently expand scope.

### Pre-existing failing tests in the suite
Run only the tests for files you touched. Note pre-existing failures in the report's "Deviations" section — do not fix them in this PR.

### Cannot satisfy an AC
Mark its row in the coverage table as ❌ with an explanation. Do not commit broken code. Surface the blocker so review can address it.

---

## Success Criteria

- **TDD_DISCIPLINE**: Every behavior went RED → GREEN; no production code without a failing test
- **AC_COVERAGE**: Every AC has ≥1 behavior tested
- **CLEAN_GATES**: type-check + lint clean after each cycle
- **NO_SCOPE_CREEP**: Every diff line traces to an AC or its test
- **ARTIFACT_WRITTEN**: `$ARTIFACTS_DIR/implementation.md` complete
- **COMMITTED**: All changes in commits with clear messages

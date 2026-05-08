---
description: Multi-layer validation — auto-detects scope and runs CODE/HTTP/DOM/STACK gates. Writes validation.md with pass/fail per gate.
argument-hint: (no arguments — reads from workflow artifacts)
---

# MR Multi-Layer Validate

**Workflow ID**: $WORKFLOW_ID

---

## Your Mission

Verify the changes the upstream `mr-tdd-implement` step produced are not just unit-passing, but actually work end-to-end at every relevant layer.

Auto-detect which layers were touched (backend / frontend / infra) and run only the gates that apply. Each gate is a hard pass/fail. Report results in `$ARTIFACTS_DIR/validation.md`.

**Failure strategy: any gate failing fails the whole step.** Downstream `create-pr` should not proceed on red gates.

---

## Phase 1: SCOPE — What did this change touch?

### 1.1 Read implementation report

```bash
cat "$ARTIFACTS_DIR/implementation.md"
```

Extract the **Files Changed** table.

### 1.2 Categorize

```bash
git diff --name-only $BASE_BRANCH..HEAD > /tmp/changed-files.txt

GATES=""
grep -qE '^backend/' /tmp/changed-files.txt && GATES="$GATES code"
grep -qE '^backend/app/(main|api|routers)' /tmp/changed-files.txt && GATES="$GATES http"
grep -qE '^frontend/.*\.(ts|tsx|js|jsx)$' /tmp/changed-files.txt && GATES="$GATES code"
grep -qE '^frontend/(components|app)/' /tmp/changed-files.txt && GATES="$GATES dom"
grep -qE '^(docker|docker-compose\.yml|backend/Dockerfile|frontend/Dockerfile)' /tmp/changed-files.txt && GATES="$GATES stack"

# Always run code gate at minimum
GATES=$(echo "$GATES code" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "GATES_TO_RUN=$GATES"
```

| Gate | Triggered when | What it does |
|------|----------------|--------------|
| **code** | Any source file changed (always runs) | Type-check + lint + unit tests |
| **http** | `backend/app/{main,api,routers}` touched | Spin up FastAPI test client, hit changed endpoints, assert ≥1 healthy response |
| **dom** | `frontend/{components,app}` touched | Run vitest+jsdom on touched components, assert they render without throwing |
| **stack** | Docker/compose changed | `docker compose config -q` + verify build context resolves |

**PHASE_1_CHECKPOINT:**
- [ ] Changed files inventoried
- [ ] Gates list determined (`GATES_TO_RUN`)

---

## Phase 2: CODE GATE — Always runs

### 2.1 Backend (if backend/ touched)

```bash
cd backend
source .venv/bin/activate 2>/dev/null || python3.12 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]" --quiet 2>&1 | tail -2

# Lint
ruff check app/ tests/ ; RUFF_RC=$?

# Format check (don't auto-fix here — surface drift)
ruff format --check app/ tests/ ; FMT_RC=$?

# Full pytest (not just touched — catch regressions)
pytest -q ; PYTEST_RC=$?

cd ..
echo "BACKEND: ruff=$RUFF_RC fmt=$FMT_RC pytest=$PYTEST_RC"
```

If `RUFF_RC`, `FMT_RC`, or `PYTEST_RC` ≠ 0 → CODE gate **FAIL** for backend.

### 2.2 Frontend (if frontend/ touched)

```bash
cd frontend
[ -d node_modules ] || npm ci 2>&1 | tail -2

npx tsc --noEmit ; TSC_RC=$?
npx eslint --quiet . ; ESLINT_RC=$?
npm test -- --run ; VITEST_RC=$?

cd ..
echo "FRONTEND: tsc=$TSC_RC eslint=$ESLINT_RC vitest=$VITEST_RC"
```

If any RC ≠ 0 → CODE gate **FAIL** for frontend.

**PHASE_2_CHECKPOINT:**
- [ ] All applicable code gates ran
- [ ] Per-tool exit codes captured

---

## Phase 3: HTTP GATE (conditional)

Skip if `http` is not in `GATES_TO_RUN`.

### 3.1 Identify endpoints touched

```bash
grep -rE '^\+.*@router\.(get|post|put|delete|patch)' backend/ | grep -E '^\+' | head -20
# or read from the diff
git diff $BASE_BRANCH..HEAD -- 'backend/app/api/**' 'backend/app/routers/**' 'backend/app/main.py' | grep -E '^\+.*(@router|@app)\.'
```

### 3.2 Smoke-test with TestClient

Write `$ARTIFACTS_DIR/.http-smoke.py` and run it:

```python
# $ARTIFACTS_DIR/.http-smoke.py
from fastapi.testclient import TestClient
from app.main import app  # adjust import if app is elsewhere

client = TestClient(app)

# Hit health endpoint as baseline
r = client.get("/health")
assert r.status_code in (200, 404), f"unexpected health rc={r.status_code}"

# Touch each new/modified endpoint with a minimal request
# (the agent should fill these in based on the diff)
{ENDPOINT_CHECKS}

print("HTTP_SMOKE_OK")
```

```bash
cd backend && source .venv/bin/activate && python "$ARTIFACTS_DIR/.http-smoke.py" ; HTTP_RC=$?
echo "HTTP: rc=$HTTP_RC"
```

If `HTTP_RC` ≠ 0 OR output doesn't contain `HTTP_SMOKE_OK` → HTTP gate **FAIL**.

**Endpoint check rules:**
- For each new/changed route, write at least one assertion (status code expected, response shape).
- Don't try to seed full DB state — use whatever fixtures exist in `backend/tests/` if a route requires them, otherwise assert the endpoint returns the expected error code (e.g., 422 for missing body).

**PHASE_3_CHECKPOINT:**
- [ ] Endpoints inventoried
- [ ] Smoke test ran
- [ ] HTTP_SMOKE_OK printed

---

## Phase 4: DOM GATE (conditional)

Skip if `dom` is not in `GATES_TO_RUN`.

### 4.1 Identify components touched

```bash
git diff --name-only $BASE_BRANCH..HEAD -- 'frontend/components/**/*.tsx' 'frontend/app/**/*.tsx' | head -20
```

### 4.2 Run vitest in jsdom env on touched files

The repo already has `vitest.config.ts` with jsdom. Just narrow the run:

```bash
cd frontend
TOUCHED=$(git diff --name-only $BASE_BRANCH..HEAD -- 'components/**/*.tsx' 'app/**/*.tsx' | tr '\n' ' ')

if [ -n "$TOUCHED" ]; then
  # Find sibling test files (X.tsx → X.test.tsx)
  TEST_FILES=""
  for f in $TOUCHED; do
    base="${f%.tsx}"
    [ -f "${base}.test.tsx" ] && TEST_FILES="$TEST_FILES ${base}.test.tsx"
  done

  if [ -n "$TEST_FILES" ]; then
    npm test -- --run $TEST_FILES ; DOM_RC=$?
  else
    echo "WARN: components touched but no .test.tsx siblings found — DOM gate will be permissive"
    DOM_RC=0
  fi
fi
cd ..
echo "DOM: rc=$DOM_RC"
```

**Why this design:** if a touched component has no sibling test, we don't synthesize one — that's the job of `mr-tdd-implement`. We just warn and let the review agents (test-coverage) flag it.

If `DOM_RC` ≠ 0 → DOM gate **FAIL**.

**PHASE_4_CHECKPOINT:**
- [ ] Touched components inventoried
- [ ] Sibling test files run

---

## Phase 5: STACK GATE (conditional)

Skip if `stack` is not in `GATES_TO_RUN`.

### 5.1 Compose syntax + build context

```bash
docker compose config -q ; COMPOSE_CONFIG_RC=$?

# Verify each service's build context still resolves (don't actually build — slow)
docker compose config --services | while read svc; do
  ctx=$(docker compose config | yq ".services.${svc}.build.context // empty" 2>/dev/null || \
        python3 -c "import yaml,sys; d=yaml.safe_load(open('docker-compose.yml')); print(d.get('services',{}).get('${svc}',{}).get('build',{}).get('context',''))")
  if [ -n "$ctx" ] && [ ! -d "$ctx" ]; then
    echo "MISSING_BUILD_CONTEXT: $svc → $ctx"
    exit 1
  fi
done ; CONTEXT_RC=$?

echo "STACK: config=$COMPOSE_CONFIG_RC ctx=$CONTEXT_RC"
```

If either RC ≠ 0 → STACK gate **FAIL**.

**Note:** We deliberately don't run `docker compose up` — that's slow and flaky in CI. The compose-config check + context existence catches the common breaks (typos, missing dirs). If the user wants full `up` smoke they can add it as a follow-up gate.

**PHASE_5_CHECKPOINT:**
- [ ] `docker compose config` passes
- [ ] All build contexts resolve to existing dirs

---

## Phase 6: AGGREGATE — Decide pass/fail

```text
overall_status =
  ALL_PASS    if every gate that ran returned 0
  FAIL        if any gate returned non-zero
```

Set the workflow exit by writing the artifact and printing a status. The downstream `create-pr` node already depends on this node via `trigger_rule: all_success` — if any rc was non-zero, this command itself must exit non-zero.

```bash
if [ "$RUFF_RC$FMT_RC$PYTEST_RC$TSC_RC$ESLINT_RC$VITEST_RC$HTTP_RC$DOM_RC$COMPOSE_CONFIG_RC$CONTEXT_RC" != "${RUFF_RC:-0}${FMT_RC:-0}${PYTEST_RC:-0}${TSC_RC:-0}${ESLINT_RC:-0}${VITEST_RC:-0}${HTTP_RC:-0}${DOM_RC:-0}${COMPOSE_CONFIG_RC:-0}${CONTEXT_RC:-0}" ]; then
  OVERALL=FAIL
else
  # Any non-zero present
  for rc in $RUFF_RC $FMT_RC $PYTEST_RC $TSC_RC $ESLINT_RC $VITEST_RC $HTTP_RC $DOM_RC $COMPOSE_CONFIG_RC $CONTEXT_RC; do
    if [ -n "$rc" ] && [ "$rc" != "0" ]; then OVERALL=FAIL; break; fi
  done
  OVERALL=${OVERALL:-PASS}
fi
echo "OVERALL=$OVERALL"
```

---

## Phase 7: WRITE — validation.md

Write `$ARTIFACTS_DIR/validation.md`:

```markdown
# Multi-Layer Validation

**Workflow ID**: $WORKFLOW_ID
**Status**: {ALL_PASS | FAIL}
**Generated**: {ISO timestamp}

---

## Gates Run

| Gate | Status | Details |
|------|--------|---------|
| CODE (backend) | ✅/❌/skipped | ruff: rc / format: rc / pytest: rc ({N} tests) |
| CODE (frontend) | ✅/❌/skipped | tsc: rc / eslint: rc / vitest: rc ({N} tests) |
| HTTP | ✅/❌/skipped | endpoints checked: {list} |
| DOM | ✅/❌/skipped | components checked: {list} |
| STACK | ✅/❌/skipped | compose config: rc / contexts: rc |

---

## Failures

{Per failed gate: full error output, file:line if applicable, recommended action}

---

## Files validated

{count + path list}

---

## Next Step

{If ALL_PASS: "Proceed to create-pr"}
{If FAIL: "Fix the failing gate above before re-running. The workflow will retry from this node on `archon workflow run --resume`."}
```

**If FAIL, exit the command non-zero so the DAG halts:**

```bash
[ "$OVERALL" = "FAIL" ] && exit 1
```

**PHASE_7_CHECKPOINT:**
- [ ] `$ARTIFACTS_DIR/validation.md` written
- [ ] Status is ALL_PASS or FAIL (no ambiguity)
- [ ] Command exits 0 only on ALL_PASS

---

## Success Criteria

- **SCOPE_DETECTED**: Gates list derived from actual diff
- **GATES_RAN**: Each applicable gate executed (or explicitly skipped with reason)
- **HARD_FAIL**: Any non-zero rc surfaces as FAIL and exits non-zero
- **ARTIFACT_WRITTEN**: `validation.md` exists with full per-gate detail

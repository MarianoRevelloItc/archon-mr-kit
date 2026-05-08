---
description: Read-only analysis of N GitHub issues — extracts file mentions and grep-resolves function/class names against the repo. Produces overlap matrix used by mr-plan-waves.
argument-hint: (no arguments — reads issue numbers from $ARTIFACTS_DIR/.issue-numbers.txt)
---

# MR Analyze Issue Overlap

**Workflow ID**: $WORKFLOW_ID

---

## Your Mission

Para cada issue en la lista de input, hacer una **mini-investigación read-only** que produzca:

- Lista de archivos que el issue probablemente va a tocar
- Cross-reference de qué archivos comparten 2+ issues (= riesgo de conflict en paralelo)

**Output**: `$ARTIFACTS_DIR/.overlap-analysis.json` con la estructura:

```json
{
  "issues": [
    {"number": 4, "title": "...", "predicted_files": ["backend/scanner.py", "..."], "type_hint": "extends-hub"},
    ...
  ],
  "hub_files": [
    {"file": "backend/scripts/run_signal_scan.py", "issues": [4, 5, 16]},
    ...
  ],
  "waves": [
    {"id": 1, "issues": [10, 11, 12], "mode": "parallel", "reason": "no overlap between members"},
    {"id": 2, "issues": [4, 5], "mode": "sequential", "reason": "share scanner.py"}
  ]
}
```

**Golden rule**: NO TOCAR código. NO CREAR PRs. NO MODIFICAR archivos del repo. Solo leer y analizar.

---

## Phase 1: LOAD — Read input issue numbers

```bash
ISSUE_NUMS_FILE="$ARTIFACTS_DIR/.issue-numbers.txt"
if [ ! -f "$ISSUE_NUMS_FILE" ]; then
  echo "ERROR: $ISSUE_NUMS_FILE missing — upstream node must populate it" >&2
  exit 1
fi

ISSUE_NUMS=$(cat "$ISSUE_NUMS_FILE" | tr -d ' ' | tr ',' '\n' | grep -E '^[0-9]+$')
COUNT=$(echo "$ISSUE_NUMS" | wc -l | tr -d ' ')
echo "Analyzing $COUNT issues: $(echo $ISSUE_NUMS | tr '\n' ' ')"
```

**PHASE_1_CHECKPOINT:**
- [ ] Issue numbers loaded
- [ ] Count > 0

---

## Phase 2: FETCH — Get body of each issue

For each issue number:

```bash
gh issue view "$N" --json number,title,body,labels,state \
  > "$ARTIFACTS_DIR/.issue-$N.json"
```

Verify state == "open" (skip closed ones with a warning).
Verify HITL label is NOT present (skip HITL with a warning).

---

## Phase 3: PREDICT FILES per issue

Para cada issue, predecir qué archivos va a tocar usando 3 técnicas:

### Technique A — Explicit file paths in body

Buscar paths en el body del issue:

```python
import re
patterns = [
    r'`([a-zA-Z0-9_/.-]+\.(py|ts|tsx|js|jsx|md|yaml|yml|toml|json|html|css))`',  # backtick-quoted paths
    r'\b([a-zA-Z0-9_/]+/[a-zA-Z0-9_/.-]+\.[a-z]+)\b',  # bare paths with /
]
```

Cualquier match es un file path explícito.

### Technique B — Function/class names mentioned → grep

Buscar identifiers (CamelCase o snake_case) mencionados en el body. Para cada uno:

```bash
grep -rl "def $IDENT\|class $IDENT\|function $IDENT\|export.*$IDENT" \
  --include="*.py" --include="*.ts" --include="*.tsx" \
  backend/ frontend/ 2>/dev/null
```

Los archivos que matchean = candidatos a touch.

### Technique C — Architectural keywords → known hubs

Mapeo (extender según tipo de repo):

| Keyword en body | Probable hub file |
|---|---|
| "signal", "scanner", "orchestrator" | grep `scanner.py`, `orchestrator.py`, `run_*scan*.py` |
| "endpoint", "router", "API" | grep `routes.py`, `routers/*.py`, `app.py` |
| "schema", "model", "migration" | grep `models/*.py`, `schemas/*.py`, `alembic/versions/` |
| "component", "card", "page" | grep `components/*.tsx`, `app/*.tsx` |
| "store", "reducer", "context" | grep `store.ts`, `*Context.tsx`, `reducers/*.ts` |

Estos no son SF-específicos — son patrones arquitectónicos generales que cualquier repo puede tener. Si el repo no los tiene, simplemente no matchean.

### Combinar resultados

Por cada issue: union de las 3 técnicas, dedup, output como lista de paths.

```json
{
  "number": 4,
  "title": "New signal: geographic_expansion",
  "predicted_files": [
    "backend/app/signals/scanner.py",        // Technique B (grep "SignalScanner")
    "backend/scripts/run_signal_scan.py",    // Technique C (keyword "signal" → hub)
    "backend/app/llm/prompts/signals/",      // Technique A (path in body)
    "backend/tests/test_signal_scan.py"      // Inferred (tests for hub)
  ],
  "type_hint": "extends-hub"
}
```

**PHASE_3_CHECKPOINT:**
- [ ] Each issue has a predicted_files list
- [ ] No duplicates within a single issue's list

---

## Phase 4: BUILD overlap matrix

Para cada FILE que aparezca en algún `predicted_files`:

```python
hub_files = {}
for issue in analyses:
    for f in issue["predicted_files"]:
        hub_files.setdefault(f, []).append(issue["number"])

# Solo files con 2+ issues son "hubs" (sources of conflict)
hub_files = {f: issues for f, issues in hub_files.items() if len(issues) >= 2}
```

Output:

```json
"hub_files": [
  {"file": "backend/scripts/run_signal_scan.py", "issues": [4, 5, 16]},
  {"file": "backend/app/signals/scanner.py", "issues": [4, 5]}
]
```

---

## Phase 5: GROUP into waves

Algoritmo simple:

1. **Issues sin overlap con ningún otro** → Wave 1 (parallel safe)
2. **Issues que comparten files con otros** → Wave 2+ (sequential within wave)
3. Si hay 3+ issues que se solapan transitively (A↔B, B↔C), van en una sola wave secuencial

Heurística: greedy graph coloring.

```python
# Build conflict graph
conflicts = {issue["number"]: set() for issue in analyses}
for f, nums in hub_files.items():
    for a in nums:
        for b in nums:
            if a != b:
                conflicts[a].add(b)

# Wave 1: nodes with no conflicts
wave_1 = [n for n in conflicts if not conflicts[n]]

# Wave 2+: connected components, each goes sequential
remaining = set(conflicts) - set(wave_1)
waves = [wave_1]
while remaining:
    # Pick a connected component
    seed = min(remaining)
    component = {seed}
    to_explore = {seed}
    while to_explore:
        n = to_explore.pop()
        for neighbor in conflicts[n]:
            if neighbor in remaining and neighbor not in component:
                component.add(neighbor)
                to_explore.add(neighbor)
    waves.append(sorted(component))
    remaining -= component
```

Output:

```json
"waves": [
  {"id": 1, "issues": [10, 11, 12], "mode": "parallel", "reason": "no overlap between members"},
  {"id": 2, "issues": [4, 5], "mode": "sequential", "reason": "share scanner.py, run_signal_scan.py"}
]
```

**PHASE_5_CHECKPOINT:**
- [ ] Every issue is in exactly one wave
- [ ] Waves with 1 issue → mode: any (use parallel for consistency)
- [ ] Waves with 2+ issues that share files → mode: sequential
- [ ] Waves with 2+ issues that DON'T share files → mode: parallel

---

## Phase 6: WRITE — `.overlap-analysis.json`

Combine everything into the output JSON:

```json
{
  "generated_at": "{ISO timestamp}",
  "total_issues": N,
  "skipped_issues": [{"number": 9, "reason": "HITL label"}],
  "issues": [...],
  "hub_files": [...],
  "waves": [...]
}
```

Path: `$ARTIFACTS_DIR/.overlap-analysis.json`

**PHASE_6_CHECKPOINT:**
- [ ] JSON written
- [ ] All required keys present
- [ ] No syntax errors (validate with `python3 -c 'import json; json.load(open("..."))'`)

---

## Phase 7: REPORT — Brief output to user (the mr-plan-waves prompt will read the JSON for full presentation)

```
Analyzed N issues across M waves.
Detected K hub files (touched by 2+ issues).
Skipped: {list of skipped issues + reasons}

Output: $ARTIFACTS_DIR/.overlap-analysis.json
```

---

## Edge cases

- **Issue body has no clear file references**: use only Technique C (architectural keywords). If still empty → mark as "unknown overlap, recommend running solo as wave on its own".
- **Issue is HITL**: skip with note, don't include in waves.
- **Issue is closed**: skip with note.
- **Repo doesn't match any architectural keyword pattern**: technique C returns nothing, only A and B work. That's fine — the analysis is still valid, just less precise.
- **Duplicate issue numbers in input**: dedup silently.

---

## Success Criteria

- **READ_ONLY**: no file written outside `$ARTIFACTS_DIR/`, no git commits, no PRs created
- **ANALYZE_ALL**: every input issue is processed (or explicitly skipped with reason)
- **OVERLAP_DETECTED**: hub files identified
- **WAVES_BUILT**: every issue assigned to exactly one wave
- **JSON_VALID**: output parseable

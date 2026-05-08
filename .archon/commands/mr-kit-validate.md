---
description: Validate the integrity of the archon-mr-kit installation in this repo — YAML syntax, command frontmatter, requires_skills wiring, and skill references in workflow nodes.
argument-hint: (no arguments — runs from repo root)
---

# MR Kit Validate

**Workflow ID**: $WORKFLOW_ID

---

## Your Mission

Statically validate the `archon-mr-kit` artifacts in this repo and produce a pass/fail report. This is a **lint, not a runtime** — no Anthropic API calls, no `archon` CLI invocations. The same checks back the GitHub Actions smoke test (`scripts/test-bootstrap.sh`).

You will:

1. Walk every YAML in `.archon/workflows/` — assert it parses and has the required top-level keys.
2. Walk every Markdown in `.archon/commands/` — assert frontmatter parses and (optionally) declares `requires_skills:`.
3. For each workflow, walk its `nodes:` and confirm any `skills: [...]` references point to a real `.claude/skills/<name>/SKILL.md`.
4. For each command with `requires_skills: [X]`, confirm every workflow node that calls that command either:
   - lists `X` in its `skills:` array (preferred — pins the context), OR
   - has a body that grep-references `X` (best-effort — proves the command knows it depends on `X`).
5. Print a single report: one line per artifact, `OK` or `FAIL: <reason>`. Exit non-zero if any line fails.

---

## Phase 1: PREREQS

```bash
set -e

# Ensure pyyaml is available — the validator is python so it can parse YAML reliably
python3 -c "import yaml" 2>/dev/null || pip install --quiet pyyaml

# Locate the validator script (committed to the repo)
SCRIPT="scripts/test-bootstrap.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: $SCRIPT missing — kit is incomplete"
  exit 1
fi

ls .archon/workflows/ .archon/commands/ .claude/skills/
```

---

## Phase 2: RUN VALIDATOR

The repo ships with a stand-alone validator at `scripts/test-bootstrap.sh` that performs all four checks below in pure Python (no archon CLI dependency). Run it:

```bash
bash scripts/test-bootstrap.sh
```

Expected output:

```
== archon-mr-kit static validator ==
[workflows]
  .archon/workflows/mr-bootstrap-project.yaml ........... OK
  .archon/workflows/mr-idea-to-prd.yaml ................. OK
  ...
[commands]
  .archon/commands/mr-tdd-implement.md (requires: tdd) .. OK
  ...
[skills]
  .claude/skills/tdd ..................................... OK
  ...
[wiring]
  mr-issue-to-pr.implement → mr-tdd-implement (requires: tdd) — node has skills:[tdd] ✓
  ...
== PASS (N artifacts checked, 0 failures) ==
```

If the script exits non-zero, the report below must record the failures verbatim.

---

## Phase 3: WRITE REPORT

Save the validator's output to `$ARTIFACTS_DIR/kit-validation.md`:

```bash
mkdir -p "$ARTIFACTS_DIR"
bash scripts/test-bootstrap.sh > "$ARTIFACTS_DIR/kit-validation.md" 2>&1
EXIT=$?
echo "Exit: $EXIT"
exit $EXIT
```

---

## Phase 4: SUMMARY OUTPUT

```markdown
## Kit Validation

**Status**: {PASS | FAIL}
**Artifacts checked**: {N}
**Failures**: {M}

### Failures

{Bullet list of failing artifacts with reasons, or "None."}

### Next Step

If PASS, the kit is internally consistent — safe to commit / publish.
If FAIL, fix each listed issue and re-run.
```

---

## Edge Cases

### A workflow has no `skills:` arrays
Skills auto-load via Claude Code's description-matcher; explicit `skills:` is only required for **forced** loading. The validator should NOT flag a missing `skills:` array as an error — only a `skills:` array that names a skill that doesn't exist.

### A command has no `requires_skills:`
Backward-compatible: treated as "no hard requirement". Only commands with an explicit `requires_skills:` list are wiring-checked.

### A skill exists but isn't referenced anywhere
Not a failure — skills can be auto-loaded by description and never appear in YAML. The validator is one-directional: skills referenced in YAML/commands must exist; not the other way around.

### Frontmatter parsing fails
The command file is corrupt — FAIL with a clear pointer to the offending file and the parse error.

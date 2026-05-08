---
description: Read MEDIUM/LOW findings from consolidated-review.md and create GitHub follow-up issues with auto-followup label, linked to the original PR.
argument-hint: (no arguments — reads from review artifacts)
---

# MR Promote Follow-ups

**Workflow ID**: $WORKFLOW_ID

---

## Your Mission

After the review synthesis and auto-fix steps complete, the consolidated review still contains MEDIUM and LOW findings that were intentionally NOT auto-fixed (CRITICAL/HIGH only get auto-fixed by `archon-implement-review-fixes`).

Promote those leftover findings into independent GitHub issues so they don't get lost. Each issue:
- Has the `auto-followup` label (filterable)
- Links back to the originating PR
- Carries enough context for someone to grab it cold

This keeps the current PR scope tight while ensuring nothing valuable gets dropped.

---

## Phase 1: LOAD — Gather inputs

### 1.1 PR context

```bash
PR_NUMBER=$(cat "$ARTIFACTS_DIR/.pr-number" 2>/dev/null | tr -d ' \n')
PR_URL=$(cat "$ARTIFACTS_DIR/.pr-url" 2>/dev/null | tr -d ' \n')
ISSUE_NUMBER=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)

if [ -z "$PR_NUMBER" ]; then
  echo "ERROR: $ARTIFACTS_DIR/.pr-number missing — upstream create-pr step did not run"
  exit 1
fi
echo "PR=$PR_NUMBER ORIGIN_ISSUE=$ISSUE_NUMBER"
```

### 1.2 Read the consolidated review

```bash
test -f "$ARTIFACTS_DIR/review/consolidated-review.md" || {
  echo "ERROR: consolidated-review.md missing — synthesize step did not run"
  exit 1
}
cat "$ARTIFACTS_DIR/review/consolidated-review.md"
```

Also read the fix report so you know what was already addressed:

```bash
cat "$ARTIFACTS_DIR/review/fix-report.md" 2>/dev/null
```

### 1.3 Ensure label exists

```bash
gh label list --limit 200 | grep -q '^auto-followup' || \
  gh label create auto-followup --color "FBCA04" --description "Auto-promoted from PR review (MEDIUM/LOW finding)"
```

**PHASE_1_CHECKPOINT:**
- [ ] PR number and URL loaded
- [ ] consolidated-review.md present and parsed
- [ ] `auto-followup` label exists

---

## Phase 2: EXTRACT — Pull MEDIUM and LOW findings

Parse the consolidated review for issues at severity MEDIUM and LOW. The review schema (from `archon-synthesize-review`) groups findings under `## MEDIUM Issues (Options for User)` and `## LOW Issues (For Consideration)`.

For each finding, extract:
- **Title** — short imperative ("Add type guard for null family_surname")
- **Source agent** — code-review / error-handling / test-coverage / comment-quality / docs-impact
- **Location** — `path:line`
- **Severity** — MEDIUM or LOW
- **Description** — the problem statement
- **Suggested fix** — if present in the review

Already-fixed findings should be skipped: anything that appears in `fix-report.md` under a `✅ FIXED` row must NOT become a follow-up.

Build a working list:

```bash
mkdir -p "$ARTIFACTS_DIR"
cat > "$ARTIFACTS_DIR/.followups.json" <<'EOF'
[
  {
    "title": "...",
    "severity": "MEDIUM|LOW",
    "agent": "...",
    "location": "...",
    "description": "...",
    "suggested_fix": "..."
  }
]
EOF
```

**Skip-list:**
- LOW issues that are pure aesthetics (e.g., "consider renaming local variable") — only promote LOWs that have actionable code-quality, security, or correctness implications. Use judgment.
- Findings that don't have a concrete file:line reference (too vague to action).
- Duplicates — if two agents flagged the same line with similar advice, merge into one issue.

**PHASE_2_CHECKPOINT:**
- [ ] All MEDIUM findings extracted
- [ ] LOW findings filtered (only actionable ones)
- [ ] Already-fixed findings excluded
- [ ] Duplicates merged
- [ ] Working list written to `.followups.json`

---

## Phase 3: CREATE — One GitHub issue per follow-up

For each entry in `.followups.json`, create an issue:

```bash
gh issue create \
  --title "{title}" \
  --label "auto-followup" \
  --body "$(cat <<'EOF'
## Origin

Auto-promoted from PR #{PR_NUMBER} review ({severity} finding from `{agent}` agent).

- PR: {PR_URL}
- Original issue: #{ISSUE_NUMBER}

## Problem

{description}

## Location

`{location}`

## Suggested approach

{suggested_fix or "See PR review thread for context."}

## Why this is a follow-up (not in the PR)

The original PR scope was bounded to CRITICAL/HIGH findings. This {severity} item was deferred to keep the PR reviewable.

## Acceptance criteria

- [ ] {derived from description, e.g., "Type guard added at file:line"}
- [ ] Test added covering the case described above
- [ ] No regression in existing tests

---

*Auto-promoted by Archon workflow `$WORKFLOW_ID`*
EOF
)"
```

Capture the new issue number for the report:

```bash
NEW_ISSUE=$(gh issue list --label auto-followup --state open --limit 1 --json number --jq '.[0].number')
echo "$NEW_ISSUE"
```

**Rules:**
- One issue per finding. Do not bundle.
- Always cite `file:line` in the body — this is the value of follow-ups vs vague TODOs.
- If the review's suggested fix is too vague to be an AC, write a more concrete one yourself based on the description.

**PHASE_3_CHECKPOINT:**
- [ ] One issue created per follow-up
- [ ] Each issue has `auto-followup` label
- [ ] Each issue links back to PR and origin issue

---

## Phase 4: COMMENT — Update the originating PR

Post a single comment on the PR listing the new follow-up issues, so reviewers can see the full picture without hunting:

```bash
gh pr comment $PR_NUMBER --body "$(cat <<'EOF'
## 📋 Follow-ups Promoted

The review surfaced {count} MEDIUM/LOW findings outside this PR's scope. They've been filed as separate issues with the `auto-followup` label so they can be picked up independently:

| # | Severity | Title | Location |
|---|----------|-------|----------|
| #{new_issue_1} | MEDIUM | {title 1} | `{location 1}` |
| #{new_issue_2} | LOW | {title 2} | `{location 2}` |

Filter all of these: `gh issue list --label auto-followup`

---

*Promoted by Archon workflow `$WORKFLOW_ID`*
EOF
)"
```

**PHASE_4_CHECKPOINT:**
- [ ] PR comment posted with the full list
- [ ] Comment links every new issue

---

## Phase 5: WRITE — Artifact + final report

Write `$ARTIFACTS_DIR/followups-report.md`:

```markdown
# Follow-ups Report

**PR**: #{PR_NUMBER} ({PR_URL})
**Origin issue**: #{ISSUE_NUMBER}
**Generated**: {ISO timestamp}

---

## Summary

| Metric | Count |
|--------|-------|
| Findings inspected | {n} |
| MEDIUM extracted | {n} |
| LOW extracted (after filter) | {n} |
| Already-fixed skipped | {n} |
| Duplicates merged | {n} |
| Issues created | {n} |

---

## Created Issues

| # | Severity | Agent | Title | Location |
|---|----------|-------|-------|----------|
| #{n} | MEDIUM | {agent} | {title} | `{file:line}` |
| #{n} | LOW | {agent} | {title} | `{file:line}` |

---

## Skipped

| Finding | Reason |
|---------|--------|
| "{title}" | Already fixed in PR (see fix-report.md) |
| "{title}" | LOW + pure aesthetics |
| "{title}" | No actionable file:line reference |
```

Output to user (brief):

```markdown
## Follow-ups Promoted

**PR**: #{PR_NUMBER}
**New issues created**: {count} (label: `auto-followup`)

{table of new issues}

Filter: `gh issue list --label auto-followup`
```

**PHASE_5_CHECKPOINT:**
- [ ] `followups-report.md` written
- [ ] Brief output emitted

---

## Edge Cases

### No MEDIUM/LOW findings
Output: `No follow-ups to promote — review surfaced no deferred items.` Skip phases 3–4. Still write a one-line `followups-report.md` so downstream nodes don't break.

### Synthesize step was skipped (no consolidated-review.md)
This shouldn't happen if the workflow ran in order. Exit 1 with a clear error so the DAG fails visibly.

### `gh` rate limit hit while creating issues
The standard error from `gh` is informative. If creation fails partway, write what was created to `followups-report.md` so a re-run can resume from there. Do not retry blindly — surface to the user.

### Auto-followup label color/desc differs from existing
Don't reset existing labels. The `gh label create` with `--force` is not used; if the label exists with different metadata, just use it.

---

## Success Criteria

- **EXTRACTED_CORRECTLY**: All actionable MEDIUM/LOW findings captured
- **NO_DUPLICATES_OF_FIXED**: Findings already in fix-report.md are skipped
- **ISSUES_CREATED**: One GitHub issue per kept finding, all with `auto-followup` label
- **PR_LINKED**: PR has a comment listing every promoted issue
- **ARTIFACT_WRITTEN**: `followups-report.md` complete

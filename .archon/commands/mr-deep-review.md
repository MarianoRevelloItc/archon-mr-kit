---
description: Opt-in deep security review of a high-risk PR. Delegates to the security-auditor persona (and optionally code-reviewer / test-engineer agents) for axis-by-axis security audit. NOT part of the standard mr-issue-to-pr flow — invoke explicitly when a PR touches auth, secrets, crypto, or input validation.
argument-hint: <PR-number-or-branch> [--also code-reviewer,test-engineer]
---

# MR Deep Review

**Workflow ID**: $WORKFLOW_ID

---

## When to use this

Run on a PR when **any** of the following is true:

- The diff touches authentication, authorization, session handling, or password storage.
- The diff handles secrets, credentials, signing keys, or env-var-loaded creds.
- The diff implements or modifies cryptography (signing, encryption, hashing).
- The diff adds or modifies input validation for user-controllable data.
- The diff adds a new external dependency.
- The PR is labeled `security-review` or `high-risk`.

**Do NOT** run on every PR. Standard `mr-issue-to-pr` already runs `code-review`. This command is the escape hatch for PRs where the standard review's signal isn't strong enough.

---

## Your Mission

Delegate to the `security-auditor` persona (and optionally other agents) using the `Agent`/`Task` tool. Each agent runs in a **fresh context window** with its own system prompt, so its review is not contaminated by your conversation history.

You then synthesize findings into one report.

---

## Phase 1: SCOPE — Resolve the PR or branch

```bash
# Argument can be a PR number, a branch name, or empty (defaults to current branch)
TARGET="$ARGUMENTS"
if [ -z "$TARGET" ]; then
  PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")
  BRANCH=$(git branch --show-current)
elif echo "$TARGET" | grep -qE '^[0-9]+$'; then
  PR_NUMBER="$TARGET"
  BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName')
else
  BRANCH="$TARGET"
  PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q '.[0].number' 2>/dev/null || echo "")
fi

echo "PR_NUMBER=$PR_NUMBER"
echo "BRANCH=$BRANCH"

# Capture the diff for the agents
mkdir -p "$ARTIFACTS_DIR"
if [ -n "$PR_NUMBER" ]; then
  gh pr diff "$PR_NUMBER" > "$ARTIFACTS_DIR/.deep-review-diff.patch"
else
  git diff main..."$BRANCH" > "$ARTIFACTS_DIR/.deep-review-diff.patch"
fi
echo "Diff captured: $(wc -l < $ARTIFACTS_DIR/.deep-review-diff.patch) lines"
```

**PHASE_1_CHECKPOINT:**
- [ ] PR_NUMBER (or branch) identified
- [ ] Diff captured to `$ARTIFACTS_DIR/.deep-review-diff.patch`

---

## Phase 2: DELEGATE — Invoke security-auditor

Use the `Agent`/`Task` tool to invoke the `security-auditor` persona. The persona lives at `.claude/agents/security-auditor.md` — Claude Code loads its system prompt automatically from there when invoked by name.

**Critical**: pass the diff as input context, not the full repo. The persona is scope-bounded.

```
Tool: Agent (or Task, depending on Claude Code version)
Parameters:
  subagent_type: security-auditor
  description: Security audit of PR #{PR_NUMBER}
  prompt: |
    Audit this PR for exploitable security issues. Walk the 5 axes
    (input validation / auth / secrets / dependencies / crypto-and-misconfig)
    and report HIGH-confidence findings (80+) with OWASP/CWE anchors and
    concrete fix snippets.

    Scope: PR #{PR_NUMBER} (branch: {BRANCH})
    Diff: $ARTIFACTS_DIR/.deep-review-diff.patch (read this before browsing files)
    Project security baseline: docs/SECURITY.md

    Write your report to $ARTIFACTS_DIR/review/security-audit.md
    in the format defined in your system prompt.
```

If the user requested additional agents via `--also code-reviewer,test-engineer`, invoke each one in parallel. Each writes its own report to `$ARTIFACTS_DIR/review/<agent>.md`.

---

## Phase 3: SYNTHESIZE — Combine findings

After all agents complete, consolidate:

```bash
mkdir -p "$ARTIFACTS_DIR/review"
for f in "$ARTIFACTS_DIR/review/"*.md; do
  echo "=== $(basename $f .md) ==="
  cat "$f"
  echo ""
done > "$ARTIFACTS_DIR/review/deep-review-consolidated.md"
```

Then read it and extract:
- Total CRITICAL findings (90+) across all agents
- Total HIGH findings (80-89) across all agents
- Each agent's verdict (PASS / PASS_WITH_FINDINGS / BLOCK_MERGE)
- Overall recommendation: BLOCK_MERGE if any agent says so; PASS_WITH_FINDINGS if any HIGH; PASS otherwise.

---

## Phase 4: REPORT — Comment on the PR

```bash
gh pr comment "$PR_NUMBER" --body "$(cat <<'EOF'
## Deep Review Report

**Triggered by**: `mr-deep-review`
**Agents run**: security-auditor{, code-reviewer, test-engineer if requested}

### Summary

| Agent | Verdict | Critical | High |
|-------|---------|----------|------|
| security-auditor | {VERDICT} | {N} | {M} |
| code-reviewer    | {VERDICT} | {N} | {M} |
| test-engineer    | {VERDICT} | {N} | {M} |

### Overall: {BLOCK_MERGE | PASS_WITH_FINDINGS | PASS}

### Findings

{Inlined CRITICAL and HIGH findings from each agent, with file:line refs and fix snippets.}

### Out of scope
{Items each agent flagged as adjacent but not in the diff.}

---

Full consolidated report: `$ARTIFACTS_DIR/review/deep-review-consolidated.md` (artifact, not posted).
EOF
)"
```

If the overall is **BLOCK_MERGE**, also add the label `needs-human-review` to the PR:

```bash
gh pr edit "$PR_NUMBER" --add-label needs-human-review
```

**PHASE_4_CHECKPOINT:**
- [ ] PR comment posted with summary table
- [ ] `needs-human-review` label applied if BLOCK_MERGE
- [ ] Final report path printed for the user

---

## Edge cases

### Agent invocation fails

If the `security-auditor` persona file doesn't exist (`.claude/agents/security-auditor.md`), the kit may not be installed or the bootstrap workflow hasn't run:

```bash
if [ ! -f .claude/agents/security-auditor.md ]; then
  echo "ERROR: .claude/agents/security-auditor.md missing. Run mr-bootstrap-project to install kit personas."
  exit 1
fi
```

### Diff is huge (> 1000 lines)

Security auditors lose precision on huge diffs. If the diff exceeds 1000 lines, suggest splitting the PR before audit. Add a comment to the PR:

```
This PR exceeds 1000 lines — consider splitting before deep review for higher signal.
```

Continue the audit anyway; just note the warning at the top of the report.

### No PR yet (just a branch)

The command works on a branch without a PR — it just can't post comments back. Output the report to stdout and to `$ARTIFACTS_DIR/review/`.

---

## Success criteria

- **DELEGATED**: At least the `security-auditor` persona was invoked via the Agent tool with the diff as scope.
- **REPORTED**: A `deep-review-consolidated.md` exists in `$ARTIFACTS_DIR/review/`.
- **COMMUNICATED**: A PR comment was posted (or, if no PR, the report was printed to stdout).
- **LABELED**: If BLOCK_MERGE, the PR has `needs-human-review`.

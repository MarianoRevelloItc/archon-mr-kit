# 0.1.1 — 2026-05-08

## Fixed
- `mr-kit-sync` (#127): when project's FROM tag doesn't exist on kit (pre-v1
  projects or invented version strings), BASE was falling back to `kit/main`
  which equals TARGET, producing an empty sync. Now BASE is treated as an
  empty synthetic tree (sentinel `__EMPTY__`) so every TARGET file lands as
  Case A "new upstream file" and gets adopted cleanly.
- `mr-kit-sync` artifact pollution: `.archon/artifacts/runs/.../*` (transient
  workflow scratch) was being committed into sync PRs. Now the commit step
  resets `.archon/artifacts/` from the index before committing.

# Kit Changelog

All notable changes to the `archon-mr-kit` template are recorded here. The kit follows [SemVer](https://semver.org/): MAJOR.MINOR.PATCH.

The version exposed via `.archon/KIT_VERSION` is read by `mr-kit-sync` to compute upgrade deltas. Do not edit `KIT_VERSION` by hand on a project — let `mr-kit-sync` bump it.

---

## 0.1.0 — initial template release with 6 workflows, 4 commands, 6 skills

Initial extraction of the `mr-*` workflow kit from the Sales-Finder pilot into a reusable template.

### Workflows (6)

- `mr-bootstrap-project` — bootstrap a new repo with `.archon/` + labels + PR template + CLAUDE.md.
- `mr-idea-to-prd` — fuzzy idea → PRD GitHub issue (3 interactive grilling gates).
- `mr-prd-to-issues` — PRD → N child implementation issues with AFK/HITL labels.
- `mr-issue-to-pr` — single issue → review-ready draft PR using strict TDD + multi-layer validation.
- `mr-issue-to-pr-ralph` — same DAG plus rebase-against-main and conditional auto-merge.
- `mr-plan-waves` — N issues → overlap analysis → sequential and parallel run scripts.

### Commands (4)

- `mr-tdd-implement` — strict red→green per behavior, writes `implementation.md`.
- `mr-multi-validate` — auto-detects scope and runs CODE/HTTP/DOM/STACK gates.
- `mr-promote-followups` — MEDIUM/LOW review findings → `auto-followup` issues.
- `mr-analyze-issue-overlap` — read-only file/symbol overlap matrix for `mr-plan-waves`.

### Skills (6)

- `archon` — Archon CLI delegation, workflow/command authoring.
- `tdd` — red-green-refactor with vertical slicing.
- `to-prd` — convert conversation into a PRD issue.
- `to-issues` — break a plan into vertical-slice GitHub issues.
- `grill-me` — interview-style design review.
- `improve-codebase-architecture` — deepening / refactor opportunities informed by ADRs.

### Docs

- `MR-Archon.md` — kit operations manual (Spanish, single source of truth for `archon` CLI usage).
- `OPERATIONS.md` — per-project operations runbook template.
- `MANUAL.md` — long-form workflow handbook.

### Infra

- `.claude/hooks/check-on-edit.sh` — single edit-time hook (lint reminder).
- GitHub remote: `https://github.com/MarianoRevelloItc/archon-mr-kit`.

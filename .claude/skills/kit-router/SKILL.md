---
name: kit-router
description: Use when starting any archon-mr-kit workflow run, when picking which skill to load for a specific task, or when an agent feels lost about which kit capability applies. Lists every kit skill with a one-line "load when X" trigger so the calling agent can self-route without scanning the full catalog.
---

# Kit Router

You are running inside the **archon-mr-kit** template. This skill is a meta-index of every other skill the kit ships. Use it to **route**: pick which skill(s) to actually load, then stop.

This skill is **not a worker**. It tells you where to go. After consulting it, hand off to the relevant skill.

---

## How skills load in this kit

Two mechanisms:

1. **Description-driven autoload** — Claude Code reads each `SKILL.md`'s `description:` field and loads matching skills automatically based on user message. Tight descriptions → fewer false positives. The default for most skills.
2. **YAML force-load** — A workflow node can declare `skills: [<name>, ...]`, which **pins** that skill into context for that node's run. Use only when a skill is *required every time* the node runs (e.g., `tdd` on the `implement` node).

If you're unsure which to use: **default to autoload**. Force-load is for hard requirements only — it costs context tokens whether the node needs it or not.

See `docs/SKILLS-CATALOG.md` for the full taxonomy and bucket-by-bucket breakdown.

---

## Skill index

### Universal — autoload always relevant

| Skill | Load when |
|-------|-----------|
| `archon` | User mentions running, creating, or configuring archon workflows / commands. Setup or init questions about `.archon/`. |
| `tdd` | Writing or fixing code for a behavior change. Force-loaded on `mr-issue-to-pr.implement` so this is rarely autoloaded — if you're loading it manually you're probably outside the standard workflow. |
| `kit-router` | (this skill) Anytime you're orienting on which other skill applies. |

### Universal — autoload on relevant context (default-off)

| Skill | Load when |
|-------|-----------|
| `to-prd` | User wants to convert a conversation/idea into a Product Requirements Document GitHub issue. |
| `to-issues` | User wants to break a plan/spec/PRD into independently grabbable GitHub issues using vertical slices. |
| `grill-me` | User wants to stress-test a plan or design via Socratic interview — they explicitly say "grill me" or "stress-test this". |
| `improve-codebase-architecture` | User wants to find refactor / deepening opportunities, or asks to make the codebase more AI-navigable. |
| `security-and-hardening` | Implementing/reviewing auth, handling secrets, validating inputs, before prod deploy. |
| `debugging-and-error-recovery` | Bug investigation, CI failure, exception in prod, workflow run failed for non-obvious reasons. |
| `documentation-and-adrs` | Introducing a new architectural choice, writing public APIs, onboarding a teammate. |
| `source-driven-development` | Introducing a new library, choosing between API methods, depending on undocumented behavior. |

### Stack-specific — copied by `mr-bootstrap-project` only when the stack is detected

| Skill | Bootstrap copies it when |
|-------|--------------------------|
| `frontend-ui-engineering` | `package.json` lists React / Vue / Svelte / Solid / Angular. |
| `browser-testing-with-devtools` | (same trigger as above — they pair) |
| `ci-cd-and-automation` | `.github/workflows/` exists OR user opts in. |

These live under `.claude/skills/_optional/` in the template. Bootstrap copies them into `.claude/skills/<name>/` on the target repo when the trigger fires; they then become regular autoload skills in that project.

### Personas (different mechanism)

Personas are not skills — they're Claude Code subagents that live in `.claude/agents/<name>.md` and are invoked via the `Agent`/`Task` tool. The kit ships:

| Persona | Invoke via |
|---------|------------|
| `security-auditor` | `mr-deep-review` command (opt-in, not part of standard `mr-issue-to-pr`). |

---

## Routing examples

| User says | Route to |
|-----------|----------|
| "Create a workflow that..." | `archon` |
| "Implement issue #7 with TDD" | `tdd` (already force-loaded on the implement node — no manual load needed) |
| "I have an idea for a feature, help me write a PRD" | `to-prd` |
| "This PRD is huge — break it into issues" | `to-issues` |
| "Why is this CI run red?" | `debugging-and-error-recovery` |
| "Add auth to this endpoint" | `security-and-hardening` |
| "Why did we choose Postgres over MySQL? — record this" | `documentation-and-adrs` (write an ADR) |
| "Use the new fastapi auth helper" | `source-driven-development` (cite the FastAPI docs in your commit) |
| "Refactor this sprawling module" | `improve-codebase-architecture` |
| "Stress-test my migration plan" | `grill-me` |
| "Review this PR for security issues" | `mr-deep-review` command (delegates to `security-auditor` persona) |

---

## When NOT to load skills

- The user is asking a one-line question that can be answered without methodology.
- You're in a node with `context: fresh` and the workflow doesn't declare `skills:` — trust the description-matcher.
- The skill name is unfamiliar — check this index before guessing.

---

## See also

- `docs/SKILLS-CATALOG.md` — full taxonomy with rationale per bucket.
- `MR-Archon.md` § "Skills catalog and loading model" — top-level explanation of autoload vs force-load.

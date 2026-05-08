# Skills Catalog

Human-readable index of every skill the `archon-mr-kit` ships, organized by **load taxonomy**. The agent-facing version lives at `.claude/skills/kit-router/SKILL.md`.

---

## Taxonomy

We bucket skills by **how they load**, not by topic:

| Bucket | Loading mechanism | Cost |
|--------|-------------------|------|
| **Universal — default-on** | Description matches almost any kit run; nearly always relevant. | Always in context. |
| **Universal — default-off** | Description tight; loads only on relevant context. Across-stack relevance. | Loads on demand. |
| **Stack-specific** | Bootstrap copies into project `.claude/skills/` only when stack detected. | Loads on demand once installed. |
| **Skip-because-default** | Considered but rejected — already covered by Claude Code defaults or by another skill. | N/A |
| **Personas** | Subagents in `.claude/agents/`, invoked explicitly via `Agent`/`Task` tool, not autoloaded. | Per invocation. |

The reason for two universal buckets: **default-on** skills cost context every run, so we keep that bucket small (router-level meta-skills only). **default-off** skills are the workhorses — they load when their description matches.

---

## Universal — default-on

| Skill | Path | Description hint |
|-------|------|------------------|
| `kit-router` | `.claude/skills/kit-router/SKILL.md` | Meta-index. Use when orienting on which kit skill applies. |
| `archon` | `.claude/skills/archon/SKILL.md` | Run, create, or configure archon workflows / commands. |

These two are intentionally broad. `archon` is broad because nearly every kit run touches an archon concept; `kit-router` is broad because that's its *job*.

---

## Universal — default-off

| Skill | Path | Trigger |
|-------|------|---------|
| `tdd` | `.claude/skills/tdd/SKILL.md` | Building features / fixing bugs via TDD. **Force-loaded** on the `mr-issue-to-pr.implement` node — usually doesn't need to autoload separately. |
| `to-prd` | `.claude/skills/to-prd/SKILL.md` | User wants to convert a conversation into a PRD GitHub issue. |
| `to-issues` | `.claude/skills/to-issues/SKILL.md` | Break a plan / spec / PRD into vertical-slice GitHub issues. |
| `grill-me` | `.claude/skills/grill-me/SKILL.md` | Stress-test a plan via Socratic interview. |
| `improve-codebase-architecture` | `.claude/skills/improve-codebase-architecture/SKILL.md` | Find deepening / refactor opportunities. |
| `security-and-hardening` | `.claude/skills/security-and-hardening/SKILL.md` | Auth flows, secret handling, input validation, pre-deploy checks. |
| `debugging-and-error-recovery` | `.claude/skills/debugging-and-error-recovery/SKILL.md` | Bug triage, CI failure investigation, prod exceptions. |
| `documentation-and-adrs` | `.claude/skills/documentation-and-adrs/SKILL.md` | Architecture Decision Records, public API docs, onboarding READMEs. |
| `source-driven-development` | `.claude/skills/source-driven-development/SKILL.md` | Cite docs when picking libraries / methods / undocumented behavior. |

**Why default-off**: each costs ~2-5KB of context if always loaded. Across a typical workflow run with N nodes, that compounds. Description-matching pays for itself.

---

## Stack-specific (template-only until bootstrap copies)

These ship under `.claude/skills/_optional/` in the template. `mr-bootstrap-project` Phase 8b copies them into the target repo's `.claude/skills/<name>/` only when the stack matches.

| Skill | Trigger | Path (in template) |
|-------|---------|--------------------|
| `frontend-ui-engineering` | `package.json` lists React/Vue/Svelte/Solid/Angular. | `.claude/skills/_optional/frontend-ui-engineering/` |
| `browser-testing-with-devtools` | Same as above (paired). | `.claude/skills/_optional/browser-testing-with-devtools/` |
| `ci-cd-and-automation` | `.github/workflows/` exists OR user opts in at bootstrap. | `.claude/skills/_optional/ci-cd-and-automation/` |

After bootstrap copies them, they behave as regular default-off skills in the target repo.

---

## Skip-because-default

We considered but rejected adding these — they're covered elsewhere.

| Skill we did NOT add | Why |
|----------------------|-----|
| `git-hygiene` | Claude Code's default behavior + `MR-Archon.md` § 5 ("Troubleshooting") cover the kit-specific git ops. Adding a skill would duplicate. |
| `pr-template-author` | The PR template lives at `.github/pull_request_template.md`; `mr-issue-to-pr.create-pr` reads it directly. No skill needed. |
| `linting-and-formatting` | Each project's `CLAUDE.md` (created by `mr-bootstrap-project`) lists its lint/format commands. The implement node respects them via the project conventions read in Phase 0.3. |
| `pair-with-human` | Out of scope for autonomous kit. The HITL label + `grill-me` skill cover the cases where humans need to weigh in. |

---

## Personas (different mechanism)

Personas are Claude Code subagents — they live in `.claude/agents/<name>.md` with frontmatter `name`, `description`, `tools`, and a system prompt body. They are **not autoloaded**; they are invoked via the `Agent`/`Task` tool from inside a command or workflow node.

| Persona | Path | Invoke via |
|---------|------|------------|
| `security-auditor` | `.claude/agents/security-auditor.md` | `mr-deep-review` command — explicit opt-in for high-risk PRs. |

The reason to use a persona instead of a skill: deep, role-specific reviews benefit from a *fresh context window* with a curated system prompt. Skills append to the current context — personas replace it.

---

## Adding a new skill

When you add a new skill to the template:

1. Decide its bucket. If you're not sure between "universal default-off" and "stack-specific", default to **stack-specific** — it's safer not to over-load context.
2. Add the SKILL.md with a **tight** `description:` field (test: would it fire on irrelevant prompts?).
3. Update `.claude/skills/kit-router/SKILL.md`'s skill index.
4. Add a row to this catalog.
5. If it's stack-specific, add the bootstrap copy logic in `mr-bootstrap-project.yaml` Phase 8b.
6. Run `bash scripts/test-bootstrap.sh` — fails if the SKILL.md frontmatter is malformed.

---

## See also

- `MR-Archon.md` § "Skills catalog and loading model" — top-level overview.
- `.claude/skills/kit-router/SKILL.md` — agent-facing index used at routing time.

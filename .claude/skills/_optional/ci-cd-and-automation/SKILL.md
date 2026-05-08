---
name: ci-cd-and-automation
description: Use when designing or auditing CI/CD pipelines, debugging slow / flaky CI runs, planning a feature flag rollout, or wiring quality gates. Triggers on "GitHub Actions", "CircleCI", "GitLab CI", "deploy pipeline", "feature flag", "canary", "blue-green", "shift left", or any discussion of how code gets from commit to production.
---

# CI/CD and Automation

CI/CD is the conveyor belt from commit to production. It has four jobs, in priority order:

1. **Catch problems before merge** (Shift Left).
2. **Move fast** (a 30-minute CI is a productivity tax — and a temptation to skip).
3. **Fail safely** (a bad deploy gets caught early and rolled back automatically).
4. **Tell the truth** (red CI means broken; flaky CI means broken trust).

---

## When this skill applies

- Wiring up a new pipeline (GitHub Actions, CircleCI, GitLab CI, Jenkins, etc.).
- Debugging slow or flaky CI.
- Planning a feature flag or canary rollout.
- Adding a new quality gate (lint, test, audit, perf budget).
- Reviewing the *.yml under `.github/workflows/`.

---

## Shift Left — catch problems early

Each gate's cost rises by ~10× as you move right:

```
Pre-commit hook (1 sec)  →  CI (5 min)  →  Staging (1 hour)  →  Prod (incident)
        $                       $$$              $$$$$               $$$$$$$$$$
```

Move every check left where you can:

| Check | Best place |
|-------|------------|
| Linting / formatting | Pre-commit hook (catch instantly) |
| Type-check | Pre-commit + CI |
| Unit tests | CI on every PR |
| Integration tests | CI on every PR (with parallelization) |
| E2E tests | CI on `main` (or nightly), staging smoke after deploy |
| Security audit | CI on every PR (`pip-audit`, `npm audit`) |
| Bundle size budget | CI on every PR |
| Visual regression | CI on every PR (Chromatic / Percy) |
| Performance budget | Lighthouse CI on every PR |

**Anti-pattern**: making CI catch what a pre-commit hook should. The 5-minute round trip "push, see CI red, fix typo, push again" is wasted time. Pre-commit catches it in 1 second.

---

## Pipeline structure

A reasonable PR pipeline:

```yaml
name: ci
on: pull_request

jobs:
  lint:                  # ~30 sec
    steps: [checkout, setup, lint, type-check]

  unit-tests:            # ~2 min
    needs: [lint]        # cheaper jobs first
    strategy:
      matrix: [node-18, node-20]
    steps: [checkout, setup, test]

  integration-tests:     # ~5 min
    needs: [lint]
    services: [postgres, redis]
    steps: [checkout, setup, migrate, test]

  audit:                 # ~30 sec
    steps: [checkout, npm-audit, pip-audit]

  bundle-size:           # ~1 min
    steps: [checkout, build, compare-size-against-main]

  e2e:                   # ~10 min — only on main + nightly
    if: github.ref == 'refs/heads/main'
    steps: [checkout, setup, playwright-install, test]
```

Patterns that matter:

- **Cheap gates first** (`lint` before `unit-tests`). Fail fast on cheap things.
- **Parallel where possible** — `lint`, `audit`, `bundle-size` don't depend on each other.
- **Cache aggressively** — `actions/cache` for `node_modules`, `~/.cache/pip`, build artifacts.
- **Matrix only for actual coverage value** — running tests against 4 node versions when you ship 1 is waste.

---

## Quality gates (hard fail vs soft fail)

| Gate | Fail mode |
|------|-----------|
| Lint, type-check | HARD — the code can't be shipped if these fail |
| Unit + integration tests | HARD |
| Security audit (HIGH/CRITICAL CVEs in prod deps) | HARD |
| Bundle size > 5% increase | SOFT (warn) — discuss in review, may be intentional |
| Test coverage delta | SOFT — coverage targets corrupt when forced |
| Performance budget | HARD on user-facing pages, SOFT for admin dashboards |

Soft fails: fail the *check* but allow merge. Use GitHub's "required" / "non-required" status check setting.

---

## Feature flags — the safer rollout

Behind a flag, code can ship to production without being active. Decouple **deploy** from **release**.

### When to use a flag

- New feature that's still being tested with a small cohort.
- Risky migration where rollback would lose data.
- A/B experiment.
- Kill switch for a fragile dependency.

### Flag hygiene

- **Name them after the feature, not the date**: `new-checkout-flow` not `flag-2026-04`.
- **Default to OFF in production, ON in staging** so the path runs in CI.
- **Cleanup quarterly**: every flag has a birth date and a planned death date. Stale flags are technical debt — add a recurring chore to retire them.
- **Document each flag** in `docs/runbook/FEATURE-FLAGS.md` with: owner, default, on/off rollout plan, scheduled retirement.

### Flag-as-circuit-breaker

```python
if feature_flag("new-pricing-engine") and not is_emergency_disabled("new-pricing-engine"):
    return new_pricing(...)
return legacy_pricing(...)
```

The double-check (flag + emergency-disabled) lets ops kill a feature in seconds without a deploy.

---

## Deployment patterns

| Pattern | When |
|---------|------|
| **All-at-once** | Static sites, low-traffic APIs, when rollback is fast and cheap. |
| **Blue-Green** | High-traffic stateless services. Two prod envs; flip the load balancer. Fast rollback (flip back). |
| **Canary** | Critical services. Deploy to 1% → 10% → 50% → 100% with health checks at each step. |
| **Feature flag rollout** | Already-deployed code; gate the activation. The safest because no infrastructure changes. |

Whatever you pick, document it in `docs/runbook/ROLLBACK.md`.

---

## Failure feedback loop — when CI fails, who finds out

The pipeline's truth-telling job: when something breaks, the right people get notified within 5 minutes.

- **PR check failure** → GitHub UI marks the PR red. The author sees it on the PR page.
- **`main` build failure** → notification to a `#deploys` Slack channel + the author who merged.
- **Deploy failure** → page the on-call engineer (PagerDuty / Opsgenie).
- **Post-deploy smoke failure** → automatic rollback + page on-call.

The cost of NOT having this loop: bugs reach production undetected, and the team's CI signal gets noisy ("oh, that test fails sometimes, ignore it"). Once you ignore one red, you ignore all reds.

---

## Anti-patterns

| Anti-pattern | Why it's bad |
|--------------|--------------|
| "Tests are flaky, just retry the build." | Flaky tests are bugs. Retrying hides them and trains the team to ignore CI. Fix or quarantine — never auto-retry. |
| "We'll add the security audit later." | The audit becomes much harder once dep tree has grown. Add it on day 1. |
| 30-minute CI run | Engineers stop running CI locally and merge things they "think" are fine. Cap CI at 15 min — parallelize, cache, split. |
| Skipping CI with `[skip ci]` regularly | If you're skipping CI, your CI isn't useful. Make it useful or remove it. |
| Required reviewers + auto-merge in one repo | The auto-merge path bypasses reviewer requirement → review becomes optional → quality drops. Pick one. |
| Long-lived feature branches | Merge conflicts compound. Use vertical slices behind feature flags (see `documentation-and-adrs` ADR-0012 example). |

---

## Quick checklist when adding a CI job

```
[ ] Cheap jobs run first (lint before tests)
[ ] Parallelism where dependencies allow
[ ] Cache configured for deps and build artifacts
[ ] Matrix only for actual production coverage need
[ ] Failure mode (HARD vs SOFT) is intentional
[ ] Notification on `main` failure is wired
[ ] Time budget defined (and enforced — gh-actions has timeouts)
```

---

## See also

- `security-and-hardening` § Axis 4 — dependency audit details.
- `documentation-and-adrs` — record CI/CD architecture choices as ADRs.
- `debugging-and-error-recovery` — when CI fails non-obviously, the 5-step triage applies.

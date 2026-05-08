---
name: source-driven-development
description: Use when introducing a new library, choosing between API methods, writing code that depends on undocumented behavior, or pinning to a specific version because of a known quirk. Triggers on "use library X", "switch to Y", "this version has feature Z", "let's use the new API", or any commit that adds/upgrades a dependency.
---

# Source-Driven Development

**Cite. Versions change.**

Every claim about how a library / API / runtime behaves must trace to **official documentation** at a **specific version**. Not StackOverflow. Not "I remember this from last project". Not "the README example shows X" (link the README in your commit, then).

The cost of wrong assumptions: silently miscompiled code, runtime surprises, library-method behavior that flipped in a minor version. The cost of a citation: 30 seconds of `git commit -m "Source: <url>"`.

---

## When this skill applies

- Adding a new library to `pyproject.toml`, `package.json`, `Cargo.toml`, etc.
- Upgrading a major version (`fastapi 0.100` → `0.110`, `next 13` → `14`).
- Picking between two API methods in the same library (`asyncio.create_task` vs `asyncio.ensure_future`).
- Relying on behavior not obvious from the function signature (defaults, edge cases, ordering).
- Implementing something that the language/runtime spec dictates (Python's `dict` insertion-order, ECMAScript hoisting, Go's defer execution order).

If you're writing code that "should just work", run it through this skill: can you point to the docs that say it should?

---

## The discipline

### 1. Find the official source

In order of preference:

1. **Official docs** for the exact version you're using (`https://fastapi.tiangolo.com/release-notes/#0110`).
2. **The library's own README** at the tagged version on GitHub (`github.com/.../tree/v0.110.0`).
3. **The release notes / changelog** for the version that introduced the behavior.
4. **The source code** of the library, on a tagged release, if 1-3 don't cover it (then file an upstream docs issue).

Avoid:

- StackOverflow answers from before the current major version.
- AI-generated tutorials (yes, including ones I'd produce — verify against docs).
- Blog posts from > 2 years ago for fast-moving libs (Next.js, FastAPI, React).

### 2. Cite in the commit

When introducing a new lib or version-specific behavior, the commit body includes a `Source:` line:

```
feat(api): use httpx.AsyncClient with explicit follow_redirects=False

Default for follow_redirects flipped to False in httpx 0.22+; we want
the explicit form so future readers don't have to remember the flip.

Source: https://www.python-httpx.org/changelog/#0220-30th-january-2022
```

For ADRs (when the choice is architectural — see `documentation-and-adrs`):

```markdown
## Decision

We use httpx (not requests) for all outbound HTTP because we need native asyncio support.

Source: https://www.python-httpx.org/async/ (accessed 2026-04-15, httpx 0.27.0)
```

### 3. Pin the version where the cited behavior holds

If your code depends on a specific behavior, **pin the version range** that ships that behavior. A floating `^0.22` lets a future bot upgrade to `0.30` where the behavior changed silently.

```toml
# pyproject.toml
[project.dependencies]
httpx = ">=0.22,<0.30"  # follow_redirects=False default; revisit on 0.30 release
```

Document the bound in a comment.

### 4. When you can't find the source

This is itself a signal. If you searched for 5 minutes and can't find official docs for the behavior you want to depend on, **the behavior is probably undocumented** — and that means it can change in a minor version without notice. Choices:

1. **Use a different API** that IS documented. Almost always available.
2. **Run a test** that pins the behavior, so a future regression breaks loudly: `assert lib.foo() == "expected"`.
3. **File an upstream docs issue** asking the maintainer to document the behavior.

Don't write code that depends on undocumented behavior without a guard test.

---

## Anti-rationalization table

| You're thinking | The reality |
|-----------------|-------------|
| "I know this works." | Cite. Versions change. The next person who reads this code will not have your memory of 2024. |
| "It's a standard library — everyone knows how `dict` works." | Cite the docs URL anyway. "Everyone knows" claims are wrong about 30% of the time. The Python `dict` insertion-order guarantee is a 3.7+ behavior — older interpreters don't have it. |
| "The README example shows it works this way." | Link the README *at the tagged version* in your commit. README on `main` may be ahead of the version you installed. |
| "StackOverflow has 200 upvotes." | And the accepted answer is from 2019 for a library at v3, and you're using v6. Upvote count ≠ relevance to your version. |
| "I'll cite it later." | "Later" is "never". The 30 seconds it takes now saves the next reader 30 minutes. |
| "It's a tiny detail — overkill to cite." | Tiny details are exactly where regressions hide. The big architectural choices have ADRs. The tiny details have inline citations. |
| "If it breaks, the test will catch it." | Tests catch what they assert. If your test doesn't pin the cited behavior, a silent change in a transitive dep flips the behavior without test failure. |

---

## Worked example

Bad:

```python
# Use Next.js Image for the hero
import Image from 'next/image'
<Image src="/hero.png" priority />
```

Good:

```python
# Use Next.js Image with priority — preloads the LCP image (Largest Contentful Paint)
# Source: https://nextjs.org/docs/app/api-reference/components/image#priority
# (Next.js 14, accessed 2026-04-22)
import Image from 'next/image'
<Image src="/hero.png" priority alt="hero" />
```

The "good" version answers three future questions cheaply:

1. "What does `priority` do?" → linked.
2. "Which Next.js version is this for?" → 14.
3. "When was this verified?" → 2026-04-22 — if Next.js 15 changes the behavior, this comment is a flag for re-verification.

---

## Quick checklist on every PR that touches deps or version-specific code

```
[ ] Every new dep has a Source: line in the commit pointing at official docs
[ ] Every upgraded major version has an ADR or commit body explaining the diff that matters
[ ] Version pins reflect the behavior you depend on (no naked `^` for behavior-critical deps)
[ ] Anywhere you rely on undocumented behavior, there's either a citation OR a guard test
[ ] You read the actual changelog of any upgraded dep — not just "tests pass"
```

---

## See also

- `documentation-and-adrs` — when the cited behavior shapes architecture, write an ADR.
- `security-and-hardening` § Axis 4 — dep audits run alongside source citations.
- `debugging-and-error-recovery` — when a dep upgrade breaks something, the citation is the starting point of the bisect.

---
name: browser-testing-with-devtools
description: Use when investigating live-running frontend behavior — re-render storms, network waterfalls, slow paints, layout shifts, memory leaks, or bugs that only reproduce in a real browser. Triggers on "feels slow", "page is janky", "memory leak", "performance issue", "why is this re-rendering", or any UI bug that needs runtime instrumentation rather than static review.
---

# Browser testing with DevTools

Static code review can't tell you "this component re-renders 40 times per scroll event". Runtime instrumentation can. This skill is the workflow for using Chrome DevTools to extract live runtime data.

---

## When this skill applies

- A user reports the UI "feels slow" / "janky" / "lags".
- Re-renders that don't seem necessary.
- Network waterfall that blocks first paint.
- Layout shift (CLS) regressions.
- Memory growth over time.

If the bug is a deterministic logic error you can reproduce with a unit test, prefer that. DevTools is for runtime questions.

---

## The 4 panels and when to use each

### 1. Performance — for "feels slow"

```
Open DevTools → Performance tab → click ⏺ Record
→ interact with the page (the slow flow)
→ ⏹ Stop after 5-10 seconds
→ analyze
```

Read the flame chart top-down:

- **Long Tasks (>50ms)** at the top — these block the main thread. Each is a candidate for optimization.
- **Scripting** (yellow) > **Rendering** (purple) > **Painting** (green) — most apps spend the most time scripting; if rendering/painting is dominant, the issue is layout thrash or paint area.
- **FCP / LCP / CLS** markers — Web Vitals at the top of the timeline.

What to extract:
- The longest single task during the user's interaction.
- The function (or component) that dominates that task — click into it, see the call stack.

### 2. Network — for "loads slowly"

```
Open DevTools → Network → reload the page (Cmd-R / Ctrl-R)
```

Read the waterfall:

- **Critical path**: which requests block first paint? (TTFB, then HTML, then render-blocking CSS/JS.)
- **Waterfall vs parallel**: are 5 requests strictly sequential when they could fan out?
- **Sizes**: any single asset > 500KB compressed is suspect.
- **Status codes**: any 4xx/5xx? Any 304s where you wanted 200s (or vice versa)?
- **Initiator**: who fired this request? An over-eager prefetch?

Common findings:
- A bundle that's 2MB unminified.
- A `Cache-Control: no-cache` on a static asset (wrong header).
- A 1-second-blocking sync request to a third-party.
- N+1: 50 thumbnail requests fired serially because of a missing batch endpoint.

### 3. Performance Insights / Lighthouse — for Web Vitals scores

```
Open DevTools → Lighthouse → run audit
```

The output is opinionated and (mostly) actionable. The most useful sections:

- **Performance** — LCP, CLS, INP scores with specific recommendations.
- **Accessibility** — automated catches ~30% of WCAG issues (the rest need manual / screen-reader testing).
- **Best Practices** — flags `console.error`, deprecated APIs, mixed content.

Note: Lighthouse runs in a sterile environment (no extensions, throttled CPU/network). Real-user metrics from RUM (Real User Monitoring) tell a different story.

### 4. Memory — for "memory leak"

```
Open DevTools → Memory → take a Heap snapshot
→ interact with the page (open/close a modal 10×)
→ take another Heap snapshot
→ Compare → filter by Constructor delta
```

If the second snapshot has 10× more `MyModal` objects than the first, you have a leak — references to those modal instances aren't being released.

Common causes:
- Event listeners attached to `window`/`document` but never removed.
- `setInterval` / `setTimeout` not cleared on component unmount.
- Closures over large objects in long-lived callbacks.

---

## The Performance workflow (step-by-step)

For "this page feels janky":

```
1. Open DevTools → Performance → Settings: throttle CPU 4× slowdown
2. ⏺ Record
3. Reload the page, do the slow interaction once.
4. ⏹ Stop.
5. Find the longest scripting frame in the timeline.
6. Click into it → see the call stack → find the function/component.
7. Form a hypothesis: "this re-renders too often" or "this query runs on every keystroke".
8. Write a fix. Re-record. Confirm the long task is gone.
```

Don't skip step 1. Without throttling, you're testing on a top-tier dev laptop — your users aren't.

## The Network workflow

For "this page loads slowly":

```
1. Open DevTools → Network → Throttle: Slow 3G or Fast 3G
2. Hard reload (Cmd-Shift-R / Ctrl-Shift-R).
3. Sort by waterfall start time.
4. Find requests on the critical path that are:
   (a) bigger than they should be → split / lazy-load
   (b) sequential when they could be parallel → prefetch / preload / fan-out
   (c) firing at all when they could be cached → check Cache-Control / ETag
5. Apply a fix, re-test under throttling.
```

## The Re-render workflow (React-specific)

For "why is this re-rendering":

```
1. Install React DevTools (Chrome extension).
2. Open DevTools → Components → ⚙ → "Highlight updates when components render"
3. Interact with the page.
4. Components that flash on every interaction are re-rendering — even if their props didn't change.
5. Common causes:
   - Parent re-rendered, child wasn't memoized → wrap child in React.memo
   - Prop is a new function/object reference each render → useCallback / useMemo
   - Context value is a new object each render → memoize the value
6. Apply fix, retest.
```

---

## Anti-patterns

| Anti-pattern | Why it's bad |
|--------------|--------------|
| "I'll add `useMemo` everywhere just in case." | Over-memoization adds GC pressure and hurts more than it helps. Memoize when DevTools shows you the re-render is actually expensive. |
| "Lighthouse score 95 — we're done." | Lighthouse runs in a vacuum. RUM data from real users on real connections is the truth. |
| Running Performance recording without CPU throttling | Your dev laptop is not your user's phone. Throttle. |
| Trusting the Chrome DevTools mobile emulator for a11y | The emulator changes viewport + touch events. It does NOT simulate screen readers, slow CPUs accurately, or all real-device quirks. Test on real hardware. |
| Optimizing without measuring | "I think this is slow" → find out it wasn't, you optimized the wrong thing. Always profile first. |

---

## Quick checklist when investigating a "slow" complaint

```
[ ] CPU throttled to 4× (Performance tab settings)
[ ] Network throttled to Slow 3G (Network tab)
[ ] Cache disabled on reload (DevTools setting)
[ ] Recording captures the actual user complaint flow (not a synthetic flow)
[ ] Long tasks > 50ms identified
[ ] Web Vitals (LCP, CLS, INP) measured on the recording
[ ] Hypothesis formed BEFORE editing code
[ ] After fix: re-recorded and confirmed the original Long Task is gone
```

---

## See also

- `frontend-ui-engineering` — design and architecture decisions that prevent the issues this skill investigates.
- `debugging-and-error-recovery` — the general 5-step triage; this skill is the "localize" tool for runtime UI issues.
- Chrome DevTools docs: https://developer.chrome.com/docs/devtools

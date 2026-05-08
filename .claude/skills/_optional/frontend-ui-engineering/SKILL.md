---
name: frontend-ui-engineering
description: Use when designing, building, or reviewing frontend UI components. Triggers on React/Vue/Svelte/Solid/Angular work, design system questions, state management decisions, responsive design, accessibility audits, or rendering performance issues.
---

# Frontend UI Engineering

A frontend codebase decays in five places: **component architecture**, **design system consistency**, **state management complexity**, **responsive behavior**, and **accessibility**. This skill is the checklist for each.

---

## When this skill applies

- Building or refactoring a React / Vue / Svelte / Solid / Angular component.
- Picking a state management approach (local state vs context vs store).
- Designing a layout that needs to work on mobile + tablet + desktop.
- Reviewing accessibility for a feature.
- Investigating a "the UI feels slow" complaint.

If you're writing pure backend code, skip this skill.

---

## Component architecture

### One component, one concern

A component is responsible for **one** of: rendering, state, side effects, layout. Mixing all four is a code smell.

Good split:

```
<UserProfilePage>          ← layout + data fetching
  <Avatar user={user} />   ← pure rendering
  <UserBio user={user} />  ← pure rendering
  <FollowButton            ← interactive (state + side effect)
    userId={user.id}
  />
</UserProfilePage>
```

### Container / presenter (light version)

Don't over-engineer this — but for any component beyond ~200 lines, ask: "is this both fetching data AND rendering it?" If yes, extract the rendering into a presenter that takes data as props. The presenter becomes testable in isolation (Storybook, plain props), and the container becomes thin.

### Composition over inheritance

In React/Vue/Svelte, you compose. There's no `extends`. If you find yourself wanting "this component but with one prop different", that's a `Slot`/`children`/`renderProp` pattern, not a subclass.

### Avoid prop drilling > 3 levels

If a prop passes through > 3 components untouched, lift to context (React) / provide-inject (Vue) / Svelte stores. Don't reach for a global state library before measuring.

---

## Design system consistency

### Tokens, not hex codes

```tsx
// BAD
<div style={{ color: "#3b82f6", padding: 16, borderRadius: 8 }}>

// GOOD — use tokens
<div className="text-primary-500 p-4 rounded-md">
```

Hex codes / pixel values in components scatter the source of truth. Tokens (CSS variables, Tailwind, Vanilla Extract) centralize the design.

### One way to do each thing

If your codebase has both a `<Button>` from `@components/Button` and a `<button className="...">` rendered raw, you have two design systems. Pick one and migrate.

### Type contracts on every component

```tsx
// React + TypeScript
interface ButtonProps {
  variant: "primary" | "secondary" | "ghost";
  size: "sm" | "md" | "lg";
  onClick: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}
```

`variant: string` is too permissive. Tight unions catch design-system drift at the type level.

---

## State management

Pick the **least powerful** primitive that solves the problem:

| Need | Primitive |
|------|-----------|
| One component's local state | `useState` / `ref` / Svelte `let` |
| State shared across siblings | Lift to common parent |
| State shared across the tree (theme, user, locale) | Context / provide-inject / store |
| Server data (cache, refetch, dedupe) | TanStack Query / SWR / Vue Query |
| Cross-cutting client state (cart, draft form) | Zustand / Pinia / Svelte store |
| Time-travel-debug-grade state | Redux / NgRx (rarely needed) |

**Anti-pattern**: jumping straight to Redux/Zustand for every app. 80% of apps need only `useState` + TanStack Query.

### Server state ≠ client state

A common confusion: putting fetched data in Zustand/Redux. **Don't.** Server state has different concerns (cache invalidation, refetch, deduplication, optimistic updates) — use a tool built for that (TanStack Query, SWR).

---

## Responsive design

### Mobile-first

Write the smallest layout first; add wider styles via `min-width:` media queries / Tailwind `md:` / `lg:` prefixes. The reverse (desktop-first with `max-width:` queries) leaves you debugging cascading overrides.

### Touch targets

Every interactive element ≥ 44×44 CSS pixels (Apple HIG) or 48×48 (Material). Test on a real phone, not Chrome DevTools' device emulator.

### Container queries when available

```css
.card {
  container-type: inline-size;
}
@container (min-width: 400px) {
  .card-body { display: flex; }
}
```

Container queries adapt to the container's width, not the viewport — much more reusable than media queries.

---

## Accessibility (WCAG 2.1 AA checklist)

The minimum bar — there is more, but these catch ~80% of audit failures.

```
PERCEIVABLE
[ ] Every <img> has meaningful alt text (or alt="" for decorative)
[ ] Color contrast ≥ 4.5:1 for body text, ≥ 3:1 for large text and icons
[ ] Information is never conveyed by color alone (use icon + text + color)
[ ] Form inputs have <label> elements (or aria-label)
[ ] Heading order is logical (no jumping from h1 to h4)

OPERABLE
[ ] All interactive elements reachable via keyboard (Tab order is logical)
[ ] Focus indicator visible and high-contrast (don't outline:none unless replaced)
[ ] No keyboard traps (every focused element can be Tab-ed away from)
[ ] Skip-to-main-content link at the top of the page
[ ] Click targets ≥ 44×44 CSS px

UNDERSTANDABLE
[ ] Page <html lang="..."> set
[ ] Form errors clearly identified (aria-invalid, aria-describedby pointing to error)
[ ] Consistent navigation across pages

ROBUST
[ ] Semantic HTML (button is <button>, not <div onClick>)
[ ] ARIA only when semantic HTML can't express the intent
[ ] Custom components use ARIA patterns from the WAI-ARIA Authoring Practices Guide
[ ] Test with a real screen reader (NVDA on Windows, VoiceOver on macOS) — not just an automated tool
```

### Common landmines

- `<div onClick>` — should be `<button>` (free keyboard handling, focus, role).
- `outline: none` without a replacement — kills keyboard focus indicator. Use `:focus-visible` to scope.
- Toast notifications without `role="status"` — screen readers won't announce them.
- Modal without focus trap — Tab escapes to the page behind.
- Custom dropdown without `aria-expanded` / `aria-controls` / arrow-key navigation.

---

## Performance

### Measure before optimizing

Use Chrome DevTools' Performance tab (or Lighthouse) to find actual bottlenecks. Common culprits:

- **Re-renders**: an over-broad context, a non-memoized prop function. Use React DevTools Profiler.
- **Bundle size**: `next/bundle-analyzer`, `vite-bundle-visualizer`. Code-split heavy routes.
- **Images**: serve modern formats (`<picture>` with WebP/AVIF), lazy-load below-the-fold (`loading="lazy"`).
- **Fonts**: `font-display: swap`, preload critical font with `<link rel="preload">`.
- **Third-party scripts**: defer or async; consider Partytown for analytics.

The `browser-testing-with-devtools` skill covers the DevTools workflow in detail.

---

## Quick checklist before merging a UI PR

```
[ ] Component has a typed prop interface (no `any`, no naked `string` for variants)
[ ] No hex codes / pixel values — uses tokens
[ ] Tested on mobile viewport (375px width)
[ ] Keyboard-navigable (Tab through every interactive)
[ ] Focus visible on all interactives (no outline:none without replacement)
[ ] Color contrast ≥ 4.5:1 (Chrome DevTools "Contrast" check)
[ ] Bundle impact: `npm run build` shows < 50KB delta unless intentional
[ ] No console errors / warnings on page load
```

---

## See also

- `browser-testing-with-devtools` — Chrome DevTools workflows.
- `documentation-and-adrs` — record state-management framework choice as an ADR.
- WAI-ARIA Authoring Practices: https://www.w3.org/WAI/ARIA/apg/

# docs/ — microsites

This directory holds standalone microsites served by GitHub Pages. They
exist alongside the main breath app but are **deliberately isolated**
from it. The point is to let the "lattices of language" grow without
bloating the app's build, tests, or agent context.

## Isolation contract

Treat each microsite (`docs/<slug>/`) as **its own micro-repo**:

- **No imports from `packages/core`, `apps/web`, `apps/macos`, or any
  Swift package.** Microsites do not consume the breath state machine,
  the tone design, or any shared TS/Swift code.
- **No `package.json`, no `pnpm-workspace.yaml` entry.** The pnpm
  workspace explicitly excludes `docs/`. `pnpm install` and `pnpm test`
  do not see these files.
- **No build step by default.** Microsites are static HTML + CSS + JS
  (vanilla, no framework). If a future site genuinely needs a build,
  commit the built `dist/` rather than wiring it into the workspace.
- **No cross-site imports.** Site A does not read from site B. Each
  folder is fully self-contained.

The boundary is convention-enforced, not mechanical — but the
convention exists so an agent or human working on one microsite can
hold the whole thing in their head, and an agent working on the main
app can ignore this directory entirely.

## Adding a new microsite

1. Create `docs/<slug>/index.html` plus any assets it needs.
2. Make it self-contained — inline CSS/JS is fine and often clearer
   than separate files for a single-page site.
3. Add a link to it from `docs/index.html` (the landing page).
4. Commit. The next push to `main` deploys it automatically once
   Pages is configured (Settings → Pages → Source: main / docs).

URL pattern: `https://<user>.github.io/<repo>/<slug>/`

## Why not separate repos?

Co-location matters. These microsites are part of the same opus as
the breath app — variations on the same theme, written in the same
voice. Living in the same repo means one git history, one place to
find them, one commit can ship app changes alongside the essay that
explains them. The isolation contract above is what keeps that
co-location from becoming entanglement.

## What the main-app agent should do here

If you're maintaining the breath app and you find yourself in this
directory, you are probably in the wrong place. Microsite content
does not affect app behavior. App changes do not require microsite
updates. The two evolve independently.

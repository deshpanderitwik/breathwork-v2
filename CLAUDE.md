# breathwork-v2

A breathing metronome with rounds. Three surfaces (web, macOS, iOS),
one shared TypeScript state machine. See [README](README.md) for the
full architecture.

## What lives where

- `packages/core/` — shared TS: state machine, presets, tone design.
  Built to `core.iife.js` and consumed by Swift via JavaScriptCore.
- `apps/web/` — Vite SPA, deployed to Vercel on push to `main`.
- `apps/macos/`, `apps/ios/` — SwiftPM + XcodeGen apps that load the
  core JS through the `BreathRuntime` bridge.
- `swift/BreathCore/`, `swift/BreathRuntime/` — Swift packages shared
  by both Apple apps.
- `docs/` — **microsites served by GitHub Pages.** Independent of the
  app build. See [docs/CLAUDE.md](docs/CLAUDE.md). **Ignore this
  directory entirely when working on the breath app** — its contents
  do not affect app behavior, and app changes do not require updates
  here.

## Where work usually goes

- Audio / chime timing → `packages/core/src/session.ts`,
  `packages/core/src/tone-set.ts`, the platform tone-set
  implementations under `apps/web/src/audio/` and
  `swift/BreathCore/Sources/BreathCore/ToneEngine.swift`.
- UI → `apps/web/src/main.ts` (web), `apps/ios/Sources/RootView.swift`
  + `swift/BreathCore/Sources/BreathCore/SettingsView.swift` (Apple).
- New presets / tone design tweaks → `packages/core/src/presets.ts`,
  `packages/core/src/tone-design.ts`. Run `scripts/sync-core.sh` after
  any core change so Swift sees the new bundle.

## Tests

- `pnpm --filter @breathe/core test` — TypeScript contract tests.
- `cd swift/BreathRuntime && swift test` — Swift bridge + parity tests
  that load `core.iife.js` and assert event sequences are byte-equal
  to the recorded fixtures.

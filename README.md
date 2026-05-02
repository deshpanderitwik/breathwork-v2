# Breathe

A breathing metronome with rounds. Three surfaces, one breath.

The machine breathes. You fall in.

## What this is

- **macOS** — menu bar app. Left-click to start a session, right-click for settings.
- **iOS** — full-screen SwiftUI app. Background audio so it keeps running with the screen locked.
- **Web** — SPA at the deployed Vercel URL.

All three share one state machine, one tone design, one set of presets — written in TypeScript and consumed by Swift through JavaScriptCore. Audio stays native per platform because Web Audio and AVAudioEngine have genuinely different strengths.

## Architecture

```
breathwork-v2/
├── packages/
│   └── core/                            # TypeScript — single source of truth
│       ├── src/
│       │   ├── types.ts                 # SessionConfig, Phase, SessionEvent
│       │   ├── presets.ts               # Calm, Focus, Deep
│       │   ├── tone-design.ts           # Frequencies, envelope, partials
│       │   ├── tone-set.ts              # ToneSet interface
│       │   ├── session.ts               # createSession() state machine
│       │   └── index.ts
│       └── test/
│           ├── session.test.ts          # Contract tests
│           └── fixtures/*.json          # Recorded event timelines
├── apps/
│   ├── web/                             # Vite + TypeScript SPA
│   ├── macos/                           # SwiftPM executable, menu bar app
│   └── ios/                             # XcodeGen + SwiftUI app
├── swift/
│   ├── BreathCore/                      # Shared SwiftPM package
│   │   └── Sources/BreathCore/
│   │       ├── ToneEngine.swift         # AVAudioEngine implementation
│   │       ├── SessionController.swift  # Wires runtime + tones + state
│   │       ├── AppState.swift           # ObservableObject
│   │       ├── SettingsStore.swift      # UserDefaults
│   │       ├── SettingsView.swift       # SwiftUI form (shared by mac+iOS)
│   │       └── TimelineView.swift       # SwiftUI timeline strip
│   └── BreathRuntime/                   # JSC bridge to core.iife.js
└── scripts/
    ├── sync-core.sh                     # Build core, copy artifacts to Swift
    └── gen-fixtures.sh                  # Regenerate contract fixtures
```

### The trick

One state machine, written in TypeScript. The web app imports it as an ES module. The Apple apps load `core.iife.js` into a `JSContext` (JavaScriptCore is a system framework on every Mac and iPhone) and call into it from Swift via `BreathRuntime`.

Same `tone-design.ts` constants drive both the Web Audio chime and the AVAudioEngine chime — change one number, all three platforms move together. Contract-parity tests in `BreathRuntimeTests/ContractFixtureTests.swift` assert that the Swift bridge emits a byte-equal event sequence to the recorded fixtures, so JS↔Swift drift becomes a test failure.

## Build

### Web

```bash
pnpm install
pnpm --filter @breathe/core build
pnpm --filter @breathe/web dev      # local dev server
pnpm --filter @breathe/web build    # production build → apps/web/dist
```

Pushes to `main` auto-deploy to Vercel (`vercel.json` at root).

### macOS

```bash
cd apps/macos
make run                              # rebuilds, packages, launches the .app
```

The Makefile invokes `scripts/sync-core.sh` first to rebuild `@breathe/core` and copy `core.iife.js` into the Swift bundle. Without that step, the Swift app can't load the JS engine.

### iOS

```bash
cd apps/ios
make devices                          # list paired iPhones; copy the device ID
# (edit DEVICE in Makefile if it differs)
make run                              # XcodeGen → xcodebuild → install → launch
```

First run requires a free Apple Developer account (set in Xcode's Signing & Capabilities) and trusting the developer profile on the device under Settings → General → VPN & Device Management.

### Tests

```bash
pnpm --filter @breathe/core test                # 14 TS contract tests
cd swift/BreathRuntime && swift test            # 17 Swift tests, incl. parity
```

## Contracts

### `SessionConfig` → `SessionEvent[]`

The state machine is pure: given a config and a sequence of tick timestamps, it deterministically emits the same events at the same effective timestamps. Pause arithmetic lives inside the engine — host code passes monotonic `nowMs`, calls `pause()` / `resume()` at user gestures, and reads frozen elapsed time via `effectiveMs(nowMs)`.

Events are emitted at **count granularity** (one event per beat-second), not phase granularity:

```typescript
| { kind: "inhale-count"; round; beatIndex; beatsInPhase; atMs }
| { kind: "exhale-count"; round; beatIndex; beatsInPhase; atMs }
| { kind: "rest-start";   round; durationSec; fadeOutSec; atMs }
| { kind: "round-complete"; round; atMs }
| { kind: "session-complete"; atMs }
```

`beatIndex === 0` marks phase entry — UI uses that to swap labels. One event = one chime; pause cancels nothing because nothing is queued past "now."

### `ToneSet` interface

```typescript
interface ToneSet {
  playInhaleChime(): void;          // single chime, fires at currentTime
  playExhaleChime(): void;
  fadeOut(params: { fadeSec: number }): void;
  stop(): void;
}
```

Both `WebAudioToneSet` (Web Audio API) and `ToneEngine` (AVAudioEngine) implement it. Synthesis parameters come from `TONE_DESIGN` in `packages/core/src/tone-design.ts` — read at runtime by both engines through their respective bridges, so the chime is bit-identical across platforms.

## Design principles (from the PRD)

1. The app should disappear during use.
2. The machine breathes. You fall in.
3. Rest is part of the practice.
4. Settings are for between sessions.
5. Build for evolution.

## Roadmap

Shipped:
- Three surfaces with shared state machine and tone design
- Pause/resume on every surface (web, macOS, iOS)
- Background audio on iOS (continues with locked screen)
- LocalStorage / UserDefaults persistence
- Contract-parity tests for the JS↔Swift bridge

Likely next:
- iOS haptics (CHHapticEngine) for silent / pocket use
- iOS Live Activity (lock screen + Dynamic Island timeline)
- TestFlight / App Store submission
- Apple Watch companion

## Reference: v1

The Swift prototype lives at `../breathwork-v1/`. Its `BreathEngine.swift` is where the chime synthesis (fundamental + partials, exp decay envelope, AVAudioEngine plumbing) was first proven. v2's `ToneEngine` is the same math, parameterized by `TONE_DESIGN` instead of hardcoded.

# Breathe

A breathing metronome with rounds. Three surfaces, one breath.

The machine breathes. You fall in.

## What this is

- **macOS**: native SwiftUI menu bar app
- **iOS**: native SwiftUI app with background audio and haptics
- **Web**: SPA that works in any modern browser

Same state machine on every surface. Different audio implementations,
because Web Audio and AVAudioEngine have genuinely different strengths.

## Architecture

```
breathwork-v2/
├── packages/
│   └── core/                       # TypeScript state machine (single source of truth)
│       ├── src/
│       │   ├── types.ts            # SessionConfig, Phase, SessionEvent
│       │   ├── presets.ts          # Calm, Focus, Deep
│       │   ├── tone-set.ts         # ToneSet interface (per-platform impl)
│       │   ├── session.ts          # createSession() state machine
│       │   └── index.ts
│       └── test/
│           └── session.test.ts     # Contract tests = the spec
├── apps/
│   └── web/                        # SPA consuming @breathe/core as ES module
└── swift/
    ├── BreathRuntime/              # SwiftPM: JSC bridge to core.iife.js
    ├── BreathAudio/                # SwiftPM: AVAudioEngine ToneSet
    ├── BreathMac/                  # Native menu bar app (Phase 2)
    └── BreathIOS/                  # Native iOS app (Phase 2)
```

### The trick

One state machine, written in TypeScript. The web app imports it directly.
The Apple apps load it into a `JSContext` (JavaScriptCore is a system
framework on every Mac and iPhone) and call it from Swift.

Audio stays native per platform. The state machine doesn't.

## Build

```bash
pnpm install
pnpm -r build           # builds @breathe/core in two formats:
                        #   dist/index.js         (ES module, for web)
                        #   dist/core.iife.js     (IIFE global `Breathe`, for JSC)
pnpm -r test            # runs contract tests
```

Swift packages build independently:

```bash
cd swift/BreathRuntime && swift test
cd swift/BreathAudio && swift test
```

## Contracts

Two contracts define this project. Change them with intent.

### 1. `SessionConfig` → `SessionEvent[]`

The state machine is pure: given a config and a sequence of tick timestamps,
it deterministically emits the same events. Tests in
`packages/core/test/session.test.ts` encode the expected event sequences for
each preset. These are the spec.

### 2. `ToneSet` interface

```typescript
interface ToneSet {
  playInhale(params: { durationSec: number }): void;
  playExhale(params: { durationSec: number }): void;
  fadeOut(params: { fadeSec: number }): void;
  stop(): void;
}
```

Both the Web Audio and the AVAudioEngine implementations satisfy this. The
state machine never knows which one it's calling.

## Phases

This project ships in three phases so multiple agents can work in parallel.

### Phase 0 — Scaffold (done)

Monorepo, contracts, stub implementations, contract tests that define Phase 1.

### Phase 1 — Core + Runtime (two agents in parallel)

- **Agent A: TS Core.** Implements `packages/core/src/session.ts` until the
  `describe.skip(...)` contract tests all pass when un-skipped.
- **Agent B: Swift Runtime.** Implements `BreathRuntime` to load
  `core.iife.js` into a `JSContext` and expose Swift methods that mirror the
  TS API. Its tests mirror the contract tests from the TS suite.

Both depend only on the types frozen in Phase 0.

### Phase 2 — Three surfaces (three agents in parallel)

- **Agent C: Web.** Scaffolds `apps/web`, implements `WebAudioToneSet`, builds
  minimal session + settings UI.
- **Agent D: macOS.** Creates `swift/BreathMac` Xcode project — menu bar
  status item, popover window, settings panel. Uses BreathRuntime and
  BreathAudio.
- **Agent E: iOS.** Creates `swift/BreathIOS` Xcode project — SwiftUI screen,
  background audio session, optional haptics. Uses BreathRuntime and BreathAudio.

### Phase 3 — Integration

Human pass: run all three surfaces back-to-back, eyes closed, headphones on.
Verify the breath feels identical. File issues against any surface that drifts.

## Design principles (from the PRD)

1. The app should disappear during use.
2. The machine breathes. You fall in.
3. Rest is part of the practice.
4. Settings are for between sessions.
5. Build for evolution.

## Reference: v1

The Swift prototype lives at `../breathwork-v1/`. Its `BreathEngine.swift`
contains the proven audio primitives (AVAudioEngine setup, PCM buffer
envelope math, sine generation with harmonics). Phase 1's `SineToneSet` should
port these primitives, but the `Timer`-based loop is replaced by the state
machine driving `ToneSet` calls.

# @breathe/web

Web surface. Placeholder until Phase 2.

## Phase 2 tasks

1. Scaffold Vite + TypeScript (vanilla or Svelte — pick based on final preference).
2. Import `@breathe/core` directly (ES module).
3. Implement `WebAudioToneSet` satisfying the `ToneSet` interface from
   `@breathe/core`. Use the Web Audio API's `OscillatorNode` + `GainNode` for
   fade envelopes. Avoid hard cuts on sine waves (clicks).
4. Build session UI: round indicator, phase indicator, stop button. Minimal.
5. Settings form with preset selector.
6. Persist settings in localStorage or URL hash.

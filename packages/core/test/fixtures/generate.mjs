// Generate JSON fixtures for the contract tests.
//
// Each fixture is the full event sequence emitted by `createSession` driven
// with a 100ms fake clock from t=0 to total duration. The Swift test target
// loads these and asserts the JSC-driven runtime emits an identical sequence
// — drift between TS source and Swift bridge becomes a test failure.
//
// Run via: `pnpm --filter @breathe/core gen-fixtures`
// (or `scripts/gen-fixtures.sh` from the repo root, which builds first).

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createSession, PRESETS } from "../../dist/index.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const STEP_MS = 100;

function runSession(config) {
  const session = createSession(config);
  const total = session.totalDurationSec;
  const events = [...session.start(0)];
  for (let t = STEP_MS; t <= total * 1000 + STEP_MS; t += STEP_MS) {
    events.push(...session.tick(t));
  }
  return events;
}

for (const id of Object.keys(PRESETS)) {
  const events = runSession(PRESETS[id]);
  const path = join(__dirname, `${id}.json`);
  writeFileSync(path, JSON.stringify(events, null, 2) + "\n");
  console.log(`[gen-fixtures] ${id}.json — ${events.length} events`);
}

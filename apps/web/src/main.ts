import {
  DEFAULT_PRESET,
  PRESETS,
  createSession,
  type PresetId,
  type Session,
  type SessionConfig,
  type SessionEvent,
  type ToneSet,
} from "@breathe/core";
import createWebAudioToneSet from "./audio/web-audio-tone-set.js";

type PresetChoice = PresetId | "custom";

const PRESET_ORDER: PresetChoice[] = ["calm", "focus", "deep", "custom"];
const PRESET_LABELS: Record<PresetChoice, string> = {
  calm: "Calm",
  focus: "Focus",
  deep: "Deep",
  custom: "Custom",
};

interface FieldSpec {
  key: keyof SessionConfig;
  label: string;
  unit: string;
  step?: number;
}

const FIELDS: FieldSpec[] = [
  { key: "inhaleSec", label: "Inhale", unit: "sec", step: 1 },
  { key: "exhaleSec", label: "Exhale", unit: "sec", step: 1 },
  { key: "activeSec", label: "Active phase", unit: "sec", step: 10 },
  { key: "restSec", label: "Rest phase", unit: "sec", step: 5 },
  { key: "rounds", label: "Rounds", unit: "", step: 1 },
];

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

type View = "setup" | "session";

let view: View = "setup";
let activeChoice: PresetChoice = DEFAULT_PRESET;
let config: SessionConfig = { ...PRESETS[DEFAULT_PRESET] };

// In-session state
let session: Session | null = null;
let tones: ToneSet | null = null;
let rafHandle: number | null = null;
let sessionStartPerfMs = 0;
let currentPhaseLabel = "";
let currentRound = 1;

function totalDurationSec(c: SessionConfig): number {
  return c.rounds * (c.activeSec + c.restSec);
}

function formatDuration(totalSec: number): string {
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  if (sec === 0) return `${min} min`;
  return `${min} min ${sec} sec`;
}

function matchingPreset(c: SessionConfig): PresetChoice {
  for (const id of ["calm", "focus", "deep"] as PresetId[]) {
    const p = PRESETS[id];
    if (
      p.inhaleSec === c.inhaleSec &&
      p.exhaleSec === c.exhaleSec &&
      p.activeSec === c.activeSec &&
      p.restSec === c.restSec &&
      p.rounds === c.rounds
    ) {
      return id;
    }
  }
  return "custom";
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

const app = document.getElementById("app")!;

function render(): void {
  app.innerHTML = "";
  if (view === "setup") {
    app.appendChild(renderSetup());
  } else {
    app.appendChild(renderSession());
  }
}

// ---- Setup view ----

function renderSetup(): HTMLElement {
  const card = document.createElement("div");
  card.className = "card";

  const title = document.createElement("h1");
  title.className = "title";
  title.textContent = "Breathe";
  card.appendChild(title);

  card.appendChild(renderPresets());
  card.appendChild(renderFields());
  card.appendChild(renderFooter());

  return card;
}

function renderPresets(): HTMLElement {
  const group = document.createElement("div");
  group.className = "presets";
  group.setAttribute("role", "radiogroup");
  group.setAttribute("aria-label", "Preset");

  for (const choice of PRESET_ORDER) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "preset";
    btn.textContent = PRESET_LABELS[choice];
    btn.setAttribute("role", "radio");
    btn.setAttribute(
      "aria-pressed",
      activeChoice === choice ? "true" : "false",
    );
    btn.addEventListener("click", () => onPresetClick(choice));
    group.appendChild(btn);
  }

  return group;
}

function renderFields(): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "fields";

  for (const spec of FIELDS) {
    const row = document.createElement("div");
    row.className = "field";

    const labelWrap = document.createElement("label");
    labelWrap.htmlFor = `f-${spec.key}`;
    labelWrap.textContent = spec.label;
    if (spec.unit) {
      const unit = document.createElement("span");
      unit.className = "unit";
      unit.textContent = spec.unit;
      labelWrap.appendChild(unit);
    }

    const input = document.createElement("input");
    input.id = `f-${spec.key}`;
    input.type = "number";
    input.min = "1";
    input.step = String(spec.step ?? 1);
    input.value = String(config[spec.key]);
    input.addEventListener("input", () => onFieldChange(spec.key, input.value));

    row.appendChild(labelWrap);
    row.appendChild(input);
    wrap.appendChild(row);
  }

  return wrap;
}

function renderFooter(): HTMLElement {
  const footer = document.createElement("div");
  footer.className = "footer";

  const duration = document.createElement("span");
  duration.className = "duration";
  duration.textContent = `Total · ${formatDuration(totalDurationSec(config))}`;

  const start = document.createElement("button");
  start.type = "button";
  start.className = "start";
  start.textContent = "Start";
  start.addEventListener("click", onStart);

  footer.appendChild(duration);
  footer.appendChild(start);

  return footer;
}

// ---- Session view ----

function renderSession(): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "session";

  const phase = document.createElement("div");
  phase.className = "phase";
  phase.id = "phase";
  phase.textContent = currentPhaseLabel;

  const round = document.createElement("div");
  round.className = "round";
  round.id = "round";
  round.textContent = `Round ${currentRound} of ${config.rounds}`;

  const timeline = document.createElement("div");
  timeline.className = "timeline";
  timeline.id = "timeline";
  // One segment per active-or-rest phase, width proportional to duration.
  for (let r = 1; r <= config.rounds; r++) {
    const active = document.createElement("div");
    active.className = "seg seg-active";
    active.style.flexGrow = String(config.activeSec);
    const activeFill = document.createElement("div");
    activeFill.className = "seg-fill";
    active.appendChild(activeFill);
    timeline.appendChild(active);

    const rest = document.createElement("div");
    rest.className = "seg seg-rest";
    rest.style.flexGrow = String(config.restSec);
    const restFill = document.createElement("div");
    restFill.className = "seg-fill";
    rest.appendChild(restFill);
    timeline.appendChild(rest);
  }

  const stop = document.createElement("button");
  stop.type = "button";
  stop.className = "stop";
  stop.textContent = "Stop";
  stop.addEventListener("click", onStop);

  wrap.appendChild(phase);
  wrap.appendChild(round);
  wrap.appendChild(timeline);
  wrap.appendChild(stop);

  return wrap;
}

function updateTimeline(elapsedMs: number): void {
  const tl = document.getElementById("timeline");
  if (!tl) return;
  const segs = tl.children;
  const segDurations: number[] = [];
  for (let r = 1; r <= config.rounds; r++) {
    segDurations.push(config.activeSec * 1000);
    segDurations.push(config.restSec * 1000);
  }
  let cumulative = 0;
  for (let i = 0; i < segs.length; i++) {
    const seg = segs[i] as HTMLElement;
    const fill = seg.firstElementChild as HTMLElement | null;
    if (!fill) continue;
    const segStart = cumulative;
    const segEnd = cumulative + segDurations[i]!;
    let frac = 0;
    if (elapsedMs >= segEnd) frac = 1;
    else if (elapsedMs > segStart) frac = (elapsedMs - segStart) / (segEnd - segStart);
    fill.style.transform = `scaleX(${frac})`;
    cumulative = segEnd;
  }
}

function updateSessionUI(): void {
  const phaseEl = document.getElementById("phase");
  const roundEl = document.getElementById("round");
  console.log("[breathe] updateSessionUI", { currentPhaseLabel, currentRound, phaseElFound: !!phaseEl, roundElFound: !!roundEl });
  if (phaseEl) phaseEl.textContent = currentPhaseLabel;
  if (roundEl) roundEl.textContent = `Round ${currentRound} of ${config.rounds}`;
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

function onPresetClick(choice: PresetChoice): void {
  activeChoice = choice;
  if (choice !== "custom") {
    config = { ...PRESETS[choice] };
  }
  render();
}

function onFieldChange(key: keyof SessionConfig, value: string): void {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return;
  config = { ...config, [key]: n };
  activeChoice = matchingPreset(config);
  render();
}

function onStart(): void {
  console.log("[breathe] onStart", { config });
  try {
    session = createSession(config);
  } catch (err) {
    alert((err as Error).message);
    return;
  }
  try {
    tones = createWebAudioToneSet();
  } catch (err) {
    console.error("[breathe] tones init failed", err);
  }
  view = "session";
  currentPhaseLabel = "";
  currentRound = 1;
  render();
  console.log("[breathe] rendered session view", {
    phaseEl: document.getElementById("phase"),
    roundEl: document.getElementById("round"),
  });

  sessionStartPerfMs = performance.now();
  const initial = session.start(0);
  console.log("[breathe] initial events", initial);
  handleEvents(initial);

  const tick = () => {
    if (!session) return;
    const nowMs = performance.now() - sessionStartPerfMs;
    const events = session.tick(nowMs);
    if (events.length > 0) handleEvents(events);
    updateTimeline(nowMs);
    rafHandle = requestAnimationFrame(tick);
  };
  rafHandle = requestAnimationFrame(tick);
}

function onStop(): void {
  teardownSession();
  view = "setup";
  render();
}

function teardownSession(): void {
  if (rafHandle !== null) {
    cancelAnimationFrame(rafHandle);
    rafHandle = null;
  }
  if (session) {
    session.stop();
    session = null;
  }
  if (tones) {
    tones.stop();
    tones = null;
  }
}

function handleEvents(events: readonly SessionEvent[]): void {
  if (events.length > 0) console.log("[breathe] events", events);
  for (const ev of events) {
    // Update state first, then render, then touch audio — so a broken
    // audio layer cannot stop the UI from reflecting the state machine.
    switch (ev.kind) {
      case "inhale-start":
        currentRound = ev.round;
        currentPhaseLabel = "Inhale";
        break;
      case "exhale-start":
        currentRound = ev.round;
        currentPhaseLabel = "Exhale";
        break;
      case "rest-start":
        currentRound = ev.round;
        currentPhaseLabel = "Rest";
        break;
      case "round-complete":
        break;
      case "session-complete":
        break;
    }
    updateSessionUI();

    try {
      switch (ev.kind) {
        case "inhale-start":
          tones?.playInhale({ durationSec: ev.durationSec });
          break;
        case "exhale-start":
          tones?.playExhale({ durationSec: ev.durationSec });
          break;
        case "rest-start":
          tones?.fadeOut({ fadeSec: ev.fadeOutSec });
          break;
      }
    } catch (err) {
      console.error("audio error", err);
    }

    if (ev.kind === "session-complete") {
      teardownSession();
      view = "setup";
      render();
    }
  }
}

render();

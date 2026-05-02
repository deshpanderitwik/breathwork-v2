import {
  PRESETS,
  createSession,
  type Session,
  type SessionConfig,
  type SessionEvent,
  type ToneSet,
} from "@breathe/core";
import createWebAudioToneSet from "./audio/web-audio-tone-set.js";

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

const STORAGE_KEY = "breathe.session-config.v1";

// ---------------------------------------------------------------------------
// Persisted state
// ---------------------------------------------------------------------------

function loadConfig(): SessionConfig {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...PRESETS.calm };
    const parsed = JSON.parse(raw) as Partial<SessionConfig>;
    // Accept only if every field is a positive finite number; otherwise fall back.
    const needed: Array<keyof SessionConfig> = [
      "inhaleSec",
      "exhaleSec",
      "activeSec",
      "restSec",
      "rounds",
    ];
    for (const key of needed) {
      const v = parsed[key];
      if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) {
        return { ...PRESETS.calm };
      }
    }
    return parsed as SessionConfig;
  } catch {
    return { ...PRESETS.calm };
  }
}

function saveConfig(c: SessionConfig): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(c));
  } catch {
    // Storage disabled or full — fail silently, just won't persist.
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

type View = "setup" | "session";

let view: View = "setup";
let config: SessionConfig = loadConfig();

// In-session state
let session: Session | null = null;
let tones: ToneSet | null = null;
let rafHandle: number | null = null;
// Secondary driver — setInterval keeps firing (throttled to ~1s) when the
// tab is backgrounded and rAF is paused, so audio events still dispatch.
let intervalHandle: number | null = null;
let sessionStartPerfMs = 0;
let isPaused = false;
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

  card.appendChild(renderFields());
  card.appendChild(renderFooter());

  return card;
}

function renderFields(): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "fields";

  for (const spec of FIELDS) {
    const row = document.createElement("div");
    row.className = "field";

    const labelEl = document.createElement("label");
    labelEl.htmlFor = `f-${spec.key}`;
    labelEl.textContent = spec.label;

    const input = document.createElement("input");
    input.id = `f-${spec.key}`;
    input.type = "number";
    input.min = "1";
    input.step = String(spec.step ?? 1);
    input.value = String(config[spec.key]);
    input.addEventListener("input", () => onFieldChange(spec.key, input.value));

    const unitEl = document.createElement("span");
    unitEl.className = "unit";
    unitEl.textContent = spec.unit;

    row.appendChild(labelEl);
    row.appendChild(input);
    row.appendChild(unitEl);
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

  const controls = document.createElement("div");
  controls.className = "controls";

  const pauseBtn = document.createElement("button");
  pauseBtn.type = "button";
  pauseBtn.className = "pause";
  pauseBtn.id = "pause-btn";
  pauseBtn.textContent = isPaused ? "Resume" : "Pause";
  pauseBtn.addEventListener("click", onPauseResume);

  const stop = document.createElement("button");
  stop.type = "button";
  stop.className = "stop";
  stop.textContent = "Stop";
  stop.addEventListener("click", onStop);

  controls.appendChild(pauseBtn);
  controls.appendChild(stop);

  wrap.appendChild(phase);
  wrap.appendChild(round);
  wrap.appendChild(timeline);
  wrap.appendChild(controls);

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
  const pauseBtnEl = document.getElementById("pause-btn");
  if (phaseEl) phaseEl.textContent = isPaused ? "Paused" : currentPhaseLabel;
  if (roundEl) roundEl.textContent = `Round ${currentRound} of ${config.rounds}`;
  if (pauseBtnEl) pauseBtnEl.textContent = isPaused ? "Resume" : "Pause";
}

function updateDurationLabel(): void {
  const el = document.querySelector<HTMLElement>(".duration");
  if (el) el.textContent = `Total · ${formatDuration(totalDurationSec(config))}`;
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

function onFieldChange(key: keyof SessionConfig, value: string): void {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return;
  config = { ...config, [key]: n };
  saveConfig(config);
  // Surgical update — don't re-render, or the input we're typing into
  // gets replaced and loses focus.
  updateDurationLabel();
}

function onStart(): void {
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
  isPaused = false;
  currentPhaseLabel = "";
  currentRound = 1;
  render();

  sessionStartPerfMs = performance.now();
  const initial = session.start(0);
  handleEvents(initial);

  const tick = () => {
    if (!session) return;
    const nowMs = performance.now() - sessionStartPerfMs;
    // session.effectiveMs() freezes during pause — timeline halts cleanly.
    updateTimeline(session.effectiveMs(nowMs));
    const events = session.tick(nowMs);
    if (events.length > 0) handleEvents(events);
  };
  const rafLoop = () => {
    tick();
    rafHandle = requestAnimationFrame(rafLoop);
  };
  rafHandle = requestAnimationFrame(rafLoop);
  // Fallback driver for backgrounded tabs where rAF pauses.
  intervalHandle = window.setInterval(tick, 500);
}

function onPauseResume(): void {
  if (!session) return;
  const nowMs = performance.now() - sessionStartPerfMs;
  if (isPaused) {
    session.resume(nowMs);
    isPaused = false;
  } else {
    session.pause(nowMs);
    tones?.fadeOut({ fadeSec: 0.05 });
    isPaused = true;
  }
  updateSessionUI();
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
  if (intervalHandle !== null) {
    clearInterval(intervalHandle);
    intervalHandle = null;
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
  for (const ev of events) {
    switch (ev.kind) {
      case "inhale-count":
        currentRound = ev.round;
        if (ev.beatIndex === 0) currentPhaseLabel = "Inhale";
        break;
      case "exhale-count":
        currentRound = ev.round;
        if (ev.beatIndex === 0) currentPhaseLabel = "Exhale";
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
        case "inhale-count":
          tones?.playInhaleChime();
          break;
        case "exhale-count":
          tones?.playExhaleChime();
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

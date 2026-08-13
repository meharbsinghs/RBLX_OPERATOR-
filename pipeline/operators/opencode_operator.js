"use strict";

/**
 * opencode operator (https://opencode.ai — open-source terminal AI agent).
 *
 * RBLX Operator is built on top of opencode. The rblx-designer agent
 * (.opencode/agents/) is the design brain; this module drives it with any
 * model the user authenticates (DeepSeek, Claude, GPT, local models, or the
 * free OpenCode Zen tier).
 *
 * Two modes:
 *
 *   1. `design "<idea>"`  — the end-to-end design loop. OpenCode acts as the
 *      lead designer (persona + master derivation prompt), produces a complete
 *      GameSpec JSON, the pipeline compiles it into src/shared/config.luau,
 *      and the Luau validation gate runs — all in one command.
 *
 *   2. `operator "<task>"` — the engineering loop. OpenCode reads/writes the
 *      runtime itself (new systems, refactors, fixes) under the same persona,
 *      which enforces the engine contract (--!strict, constants registration,
 *      verify gate, spec-driven genericity).
 *
 * Both are loop stages, not one-shots: `fix --log` feeds runtime failures back
 * into the loop (see bridge.js).
 *
 * Usage from the CLI:
 *   node pipeline/bridge.js design "a neon extraction shooter set on a derelict space station"
 *   node pipeline/bridge.js operator "add a melee weapon system"
 *
 * Env (see .env.example):
 *   OPENCODE_MODEL          model in provider/model form (empty = opencode's configured default)
 *   OPENCODE_AGENT          agent to use (default: rblx-designer)
 *   OPENCODE_GIT_BASH_PATH  Windows only — path to git-bash.exe if opencode needs it
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = path.join(__dirname, "..", "..");
const PERSONA_PATH = path.join(__dirname, "engineer_persona.md");
const GAMES_DIR = path.join(ROOT, "games");
const { which, spawnCli } = require("../clitools");

// The engineer brain lives in its own committed file. (Inline fallback so the
// module never hard-crashes if the file is missing from a partial checkout.)
let PERSONA = null;
function getPersona() {
  if (PERSONA === null) {
    try {
      PERSONA = fs.readFileSync(PERSONA_PATH, "utf8");
    } catch {
      PERSONA = [
        "You are the senior game design engineer of the RBLX Operator engine.",
        "The game is data (src/shared/config.luau); the runtime is generic and fixed.",
        "Derive GameSpec JSON per pipeline/system_prompt.md; keep the runtime generic,",
        "register new remotes in src/shared/constants.luau, write --!strict Luau,",
        "and always end by running: node pipeline/bridge.js verify",
      ].join("\n");
    }
  }
  return PERSONA;
}

function isAvailable() {
  try {
    const bin = which("opencode");
    if (!bin) return false;
    const res = spawnCli(bin, ["--version"], { encoding: "utf8", timeout: 15000 });
    return res.status === 0;
  } catch {
    return false;
  }
}

/**
 * Run one non-interactive OpenCode task. By default the engineer persona is
 * prepended as the system context; pass `{ persona: false }` to skip it.
 * @returns {{ status: number|null, stdout: string, stderr: string }}
 */
function runTask(task, { cwd = ROOT, model, agent, timeoutMs = 900000, persona = true } = {}) {
  // A named opencode agent (e.g. rblx-designer) carries its own system prompt
  // in .opencode/agents/ — don't double-stuff the persona into the message.
  const effectivePersona = persona && !agent;
  const content = effectivePersona ? `${getPersona()}\n\n---\n\nTASK:\n${task}` : task;
  const bin = which("opencode");
  if (!bin) throw new Error("opencode CLI not found on PATH — npm i -g opencode-ai");
  const args = ["run", "--format", "json", "--auto"];
  if (agent) args.push("--agent", agent);
  if (model) args.push("--model", model);
  args.push(content);

  const res = spawnCli(bin, args, {
    cwd,
    encoding: "utf8",
    timeout: timeoutMs,
    maxBuffer: 64 * 1024 * 1024,
    env: process.env,
  });
  if (res.error) throw res.error;
  return { status: res.status, stdout: res.stdout || "", stderr: res.stderr || "" };
}

const MARK_START = "SPEC_JSON_START";
const MARK_END = "SPEC_JSON_END";

// `opencode run --format json` serializes the assistant's text as a single
// JSON-escaped string (newlines become \n, quotes \", etc.). Unescape the
// block between two markers so JSON.parse sees the real spec text.
function unescapeBlock(block) {
  return block
    .replace(/\\\\/g, "\u0000") // protect escaped backslashes first
    .replace(/\\n/g, "\n")
    .replace(/\\"/g, '"')
    .replace(/\u0000/g, "\\");
}

// Pull the block between the two markers out of any text. Iterates over every
// marked region and returns the first one that is valid JSON (the echoed task
// instructions also contain the marker names, so we never trust position —
// only parseability). Returns the raw JSON text or null.
function extractMarkedJson(text) {
  let searchFrom = 0;
  while (true) {
    const start = text.indexOf(MARK_START, searchFrom);
    if (start === -1) return null;
    const end = text.indexOf(MARK_END, start + MARK_START.length);
    if (end === -1) return null;
    const block = unescapeBlock(text.slice(start + MARK_START.length, end));
    const open = block.indexOf("{");
    const close = block.lastIndexOf("}");
    if (open !== -1 && close > open) {
      const candidate = block.slice(open, close + 1);
      try {
        JSON.parse(candidate);
        return candidate;
      } catch {
        // not this region — keep scanning
      }
    }
    searchFrom = end + MARK_END.length;
  }
}

// Newest games/*/spec.json by mtime, but ONLY if it is newer than `minTimeMs`
// (the moment this design run started). A stale spec from a previous run must
// never be compiled as if this run produced it.
function newestSpecFile(minTimeMs) {
  let best = null;
  let bestTime = 0;
  let dirs = [];
  try {
    dirs = fs.readdirSync(GAMES_DIR);
  } catch {
    return null;
  }
  for (const name of dirs) {
    const spec = path.join(GAMES_DIR, name, "spec.json");
    try {
      const stat = fs.statSync(spec);
      if (stat.isFile() && stat.mtimeMs >= minTimeMs && stat.mtimeMs > bestTime) {
        bestTime = stat.mtimeMs;
        best = spec;
      }
    } catch {
      // not a spec dir — skip
    }
  }
  return best;
}

/**
 * End-to-end design loop:
 *   idea -> OpenCode (engineer brain) derives GameSpec JSON
 *        -> pipeline compiles it into src/shared/config.luau
 *        -> Luau validation gate runs
 *
 * @param {string} idea  the game idea/goal (or path to a brief file)
 * @returns {Promise<{ok: boolean, slug?: string, specFile?: string,
 *           configFile?: string, weapons?: number, enemies?: number,
 *           verify?: {ok: boolean, issues: string[]}, log: string}>}
 */
async function designGame(idea, { model, agent } = {}) {
  const codegen = require("../codegen");
  const { validateLuau } = require("../validate_luau");
  const runStart = Date.now(); // any spec file older than this is stale

  const task = [
    "DESIGN TASK — derive one complete game design.",
    `Game idea: ${idea}`,
    "Read pipeline/system_prompt.md (the master derivation prompt) and follow its",
    "method and schema exactly. Then return ONE valid GameSpec JSON object.",
    "Rules:",
    "  - Write the JSON to games/<slug>/spec.json (slug from the game name).",
    "  - ALSO print the raw JSON between two marker lines, one per line:",
    `      ${MARK_START}`,
    "      { ... the complete JSON, nothing else ... }",
    `      ${MARK_END}`,
    "  - The JSON is the deliverable. Do not edit runtime code, codegen, or the",
    "    derivation prompt. Validate the design yourself before returning:",
    "    wallBuys reference existing weapon ids, perk placements reference",
    "    existing perk ids, zones form a connected door chain from zone 1",
    "    (door: null), colors are [r,g,b] 0-255, lighting matches the mood.",
  ].join("\n");

  const res = runTask(task, { model, agent });
  let log = [res.stdout, res.stderr].filter(Boolean).join("\n").slice(0, 12000);

  // 1) Prefer the marked JSON block; fall back to a spec file written during
  //    this run (never an older artifact).
  let specFile = null;
  const block = extractMarkedJson(res.stdout);
  if (block) {
    try {
      const parsed = JSON.parse(block);
      const slug = codegen.slugify(parsed.name || "game");
      fs.mkdirSync(path.join(GAMES_DIR, slug), { recursive: true });
      specFile = path.join(GAMES_DIR, slug, "spec.json");
      fs.writeFileSync(specFile, JSON.stringify(parsed, null, 2) + "\n");
    } catch (err) {
      return {
        ok: false,
        log: `${log}\n[design] Marker JSON failed to parse: ${err.message}`,
      };
    }
  } else {
    specFile = newestSpecFile(runStart - 1000);
  }

  if (!specFile) {
    return {
      ok: false,
      log: `${log}\n[design] No spec produced this run (no SPEC_JSON_* markers, no fresh games/*/spec.json).`,
    };
  }

  // 2) Compile through the sanctioned pipeline path.
  let result;
  try {
    const spec = await codegen.specFromPrompt("", { specFile });
    result = codegen.writeGameSpec(spec);
  } catch (err) {
    return { ok: false, log: `${log}\n[design] Compile failed: ${err.message}` };
  }

  // 3) Validation gate. The artifact is what matters — a non-zero OpenCode
  //    exit (tool errors under --auto) must not mask a valid, verified design.
  const verify = validateLuau({ print: false });
  if (res.status !== 0) {
    log += `\n[design] OpenCode exited ${res.status} — the artifact below still compiled and passed the gate; check the report for agent warnings.`;
  }

  return {
    ok: verify.ok && Boolean(specFile),
    slug: result.slug,
    specFile: result.specPath,
    configFile: result.configPath,
    weapons: result.weapons,
    enemies: result.enemies,
    perks: result.perks,
    doors: result.doors,
    zones: result.zones,
    verify: { ok: verify.ok, issues: verify.issues },
    log,
  };
}

function guidance() {
  return [
    "OpenCode CLI not found on PATH.",
    "Install:   npm i -g opencode-ai",
    "Configure a provider (e.g. DeepSeek):  opencode auth login --provider deepseek",
    "Windows note: OpenCode needs Git Bash — set OPENCODE_GIT_BASH_PATH in .env",
    "The design loop also works without OpenCode:",
    "  - node pipeline/bridge.js newgame \"<idea>\"      (DeepSeek brain)",
    "  - node pipeline/bridge.js newgame --spec out.json  (any AI chat + --spec)",
  ].join("\n");
}

module.exports = { isAvailable, runTask, designGame, getPersona, guidance, ROOT };

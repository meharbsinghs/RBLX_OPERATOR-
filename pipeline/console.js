#!/usr/bin/env node
"use strict";

/**
 * RBLX Operator — interactive console (rblxoperator).
 *
 * An always-on operator terminal: type anything in natural language and the
 * console routes it — "hi operator design a zombie survival game" designs a
 * game, "add a melee weapon" runs the engineering loop, "/arch" shows the
 * architecture. Everything the one-shot CLI can do, from one prompt.
 *
 * First launch asks to connect to Roblox Studio (the CLI works in tandem with
 * Studio: build -> open -> rojo serve -> live edit).
 *
 * Run with:  rblxoperator   (or:  rblx console)
 * The brain is opencode (rblx-designer agent) with any model provider —
 * DeepSeek, Claude, GPT, Freebuff, local — see `rblx prompt` and /arch.
 */

const fs = require("fs");
const path = require("path");
const readline = require("readline");
const { spawnSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const BRIDGE = path.join(__dirname, "bridge.js");
const ascii = require("./ascii_banner");
const { which } = require("./clitools");

/* ------------------------------------------------------------------ *
 * First-run state (.rblx/state.json — gitignored)
 * ------------------------------------------------------------------ */
const STATE_DIR = path.join(ROOT, ".rblx");
const STATE_FILE = path.join(STATE_DIR, "state.json");

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
  } catch {
    return { firstRun: true, studioConnected: false };
  }
}

function saveState(state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2) + "\n");
}

/* ------------------------------------------------------------------ *
 * Colors — the logo palette (gray body, orange accent)
 * ------------------------------------------------------------------ */
const USE_COLOR = process.stdout.isTTY && !process.env.NO_COLOR && process.env.TERM !== "dumb";
const GRAY = "\x1b[38;5;246m";
const ORANGE = "\x1b[38;5;214m";
const RESET = "\x1b[0m";
const paint = (code, s) => (USE_COLOR ? `${code}${s}${RESET}` : s);
const gray = (s) => paint(GRAY, s);
const orange = (s) => paint(ORANGE, s);

/* ------------------------------------------------------------------ *
 * Studio connection (first-run request + /studio)
 * ------------------------------------------------------------------ */
function studioInstalled() {
  const candidates = [
    path.join(process.env.LOCALAPPDATA || "", "Roblox", "Versions"),
    "C:\\Program Files (x86)\\Roblox",
  ];
  return candidates.some((p) => {
    try {
      return fs.readdirSync(p).length > 0;
    } catch {
      return false;
    }
  });
}

function rojoVersion() {
  const bin = which("rojo");
  if (!bin) return null;
  const res = spawnSync(bin, ["--version"], { encoding: "utf8", timeout: 15000 });
  return res.status === 0 ? (res.stdout || "").trim().split(/\s+/)[0] : null;
}

function runBridge(args) {
  const res = spawnSync(process.execPath, [BRIDGE, ...args], {
    cwd: ROOT,
    stdio: "inherit",
    env: process.env,
  });
  return res.status === 0 || res.status === null;
}

// The first-run Studio connect request. Returns nothing; marks state.
function requestStudioConnect(state) {
  console.log("");
  console.log(gray("── Roblox Studio link ────────────────────────────────"));
  const studio = studioInstalled();
  const rojo = rojoVersion();
  console.log(`  ${studio ? "✓" : "✗"} Roblox Studio   ${studio ? "installed" : "install at https://www.roblox.com/create"}`);
  console.log(`  ${rojo ? "✓" : "✗"} Rojo            ${rojo ? rojo : "install via scripts/studio.ps1"}`);
  console.log("");
  console.log(gray("  RBLX Operator works in tandem with Roblox Studio: I build the"));
  console.log(gray("  .rbxl, you open it, and rojo serve live-syncs every edit."));
  if (studio && rojo) {
    console.log(gray("  Connecting now: building the reference game + printing serve steps..."));
    runBridge(["build"]);
  }
  console.log("");
  console.log(gray("  To connect Studio:"));
  console.log(gray("    1. rojo build default.project.json -o RBLXOperator.rbxl"));
  console.log(gray("    2. Open RBLXOperator.rbxl in Roblox Studio (double-click it)"));
  console.log(gray("    3. Install the Rojo plugin: https://www.roblox.com/library/7168068472/Rojo"));
  console.log(gray("    4. Run: rojo serve default.project.json  → in Studio: Plugins → Rojo → Connect"));
  console.log(gray("  (Re-run anytime with /studio)"));
  state.studioConnected = studio && Boolean(rojo);
}

/* ------------------------------------------------------------------ *
 * Help + architecture
 * ------------------------------------------------------------------ */
function printHelp() {
  console.log(`
${orange("rblxoperator")} — just talk to it. Examples:

  ${orange("hi operator design this")}          describe a game → I design it end-to-end
  ${orange("design a zombie survival game")}     design loop via opencode (rblx-designer agent)
  ${orange("add a double-jump powerup")}         engineering loop — I edit the runtime
  ${orange("new game a fishing RPG")}            quick spec derivation (any model / offline)
  ${orange("doctor")}                            toolchain health check
  ${orange("connect to studio")}                 link Roblox Studio (tandem mode)

Slash commands:

  /help              this panel
  /arch              system architecture
  /design <idea>     design loop: idea → GameSpec → config.luau → verify
  /operator <task>   engineering loop: runtime edits via the agent
  /newgame <idea>    quick spec derivation
  /doctor            toolchain + environment check
  /verify            validate all Luau + JS
  /build             print Rojo build steps
  /serve             print live-sync (rojo serve) steps
  /studio            connect / reconnect Roblox Studio
  /prompt            print the master derivation prompt (works with ANY AI)
  /banner            print BUILDER BOI
  /quit              leave the console
`);
}

function printArch() {
  console.log(`
${orange("RBLX Operator — architecture")}

  one prompt ──▶ one complete, playable Roblox game

  ${gray("you")} ──▶ ${orange("rblxoperator console")} ──▶ opencode (rblx-designer agent)
                    │            │
                    ▼            ▼
        master derivation   engineering loop
        prompt (system_     (runtime edits,
        prompt.md)          fix --log feedback)
                    │
                    ▼
        GameSpec JSON (games/<slug>/spec.json)
                    │
                    ▼
        codegen ──▶ src/shared/config.luau   (the game IS data)
                    │
                    ▼
        generic runtime: weapons/enemies/zones/shop read config
                    │
                    ▼
        Rojo ──▶ RBLXOperator.rbxl ──▶ Roblox Studio (tandem: rojo serve)

  Providers: any model opencode supports — DeepSeek, Claude, GPT,
  Freebuff, local. OPENCODE_MODEL in .env picks one; the prompt is
  provider-agnostic (rblx prompt / --spec works in ANY AI chat).
  Assets: Meshy 3D → Open Cloud upload → live rbxassetid:// links.
`);
}

/* ------------------------------------------------------------------ *
 * Natural-language routing
 * ------------------------------------------------------------------ */
const GREETINGS = /^(hi|hello|hey|yo|sup|hiya|howdy|whats up|what's up|good (morning|afternoon|evening)|please|can you|could you|would you|hey there|ok|okay|alright)[,!\s]+/i;

function stripGreeting(text) {
  let t = text.trim().replace(GREETINGS, "").trim();
  // "hi operator design this" → operator is a role word, not part of the idea
  t = t.replace(/^(operator|rblx|boi|boss)[,\s]+/i, "").trim();
  return t;
}

// Route free text to an intent. Returns { intent, args } where args is the
// list of extra CLI args (e.g. the idea text) or [] when none.
function route(input) {
  const raw = input.trim();
  if (!raw) return { intent: "empty", args: [] };

  // slash commands
  if (raw.startsWith("/")) {
    const [cmd, ...rest] = raw.slice(1).split(/\s+/);
    return { intent: "slash", cmd: cmd.toLowerCase(), args: [rest.join(" ")] };
  }

  const t = stripGreeting(raw);
  const low = t.toLowerCase();

  // explicit design / make / create a game
  if (/^(design|make|create|build|develop|craft)\b/.test(low) || /(make|create|build|design)\s+(me\s+)?(a|an|the)\s+(game|obby|shooter|simulator|experience|world|map)\b/.test(low)) {
    const idea = t
      .replace(/^(design|make|create|build|develop|craft)\b/i, "")
      .replace(/(make|create|build|design)\s+(me\s+)?(a|an|the)\s+(game|obby|shooter|simulator|experience|world|map)\b/i, "")
      .replace(/^[:\-—, ]+/, "")
      .trim();
    return { intent: "design", args: [idea] };
  }

  // "new game <idea>"
  if (/^new\s+game\b/i.test(low)) {
    const idea = t.replace(/^new\s+game\b/i, "").replace(/^[:\-—, ]+/, "").trim();
    return { intent: "newgame", args: [idea] };
  }

  // engineering loop: add/fix/edit/refactor/implement/remove/change
  if (/^(add|fix|edit|refactor|implement|remove|change|update|upgrade|improve|rewrite|delete|patch|tune|balance|make\s+the)\b/.test(low)) {
    return { intent: "operator", args: [t] };
  }

  // plain intent words
  if (/\b(doctor|health\s*check|status)\b/.test(low)) return { intent: "doctor", args: [] };
  if (/\b(verify|validate|check the code)\b/.test(low)) return { intent: "verify", args: [] };
  if (/\bbuild\b/.test(low)) return { intent: "build", args: [] };
  if (/\b(serve|live[- ]sync)\b/.test(low)) return { intent: "serve", args: [] };
  if (/\b(studio|connect)\b/.test(low)) return { intent: "studio", args: [] };
  if (/\b(help|what can you do|commands)\b/.test(low)) return { intent: "help", args: [] };
  if (/\b(arch|architecture|how does this work|how it works)\b/.test(low)) return { intent: "arch", args: [] };
  if (/^(hi|hello|hey|yo|sup|hiya|howdy|good (morning|afternoon|evening))[!\s]*$/i.test(raw)) {
    return { intent: "greet", args: [] };
  }
  if (/^(prompt|system prompt)\b/.test(low)) return { intent: "prompt", args: [] };
  if (/^(banner|boi)\b/.test(low)) return { intent: "banner", args: [] };
  if (/^(quit|exit|bye|goodbye|see ya|cya)\b/.test(low)) return { intent: "quit", args: [] };

  // fallback: if it mentions a game idea vaguely, treat as design
  if (/(game|obby|shooter|simulator|rpg|world|map|mode|zombie|racing|fishing|horror|tycoon)/.test(low)) {
    return { intent: "design", args: [t] };
  }
  return { intent: "unknown", args: [raw] };
}

function handleSlash(cmd, arg, state) {
  switch (cmd) {
    case "help": case "?": printHelp(); break;
    case "arch": printArch(); break;
    case "design": return designFlow(arg);
    case "operator": return operatorFlow(arg);
    case "newgame": return newgameFlow(arg);
    case "doctor": runBridge(["doctor"]); break;
    case "verify": runBridge(["verify"]); break;
    case "build": runBridge(["build"]); break;
    case "serve": runBridge(["serve"]); break;
    case "studio": requestStudioConnect(state); break;
    case "prompt": runBridge(["prompt"]); break;
    case "banner": console.log(ascii.banner({ color: USE_COLOR })); break;
    case "quit": case "exit": case "q": console.log(gray("bye — back to the grid.")); process.exit(0); break;
    default:
      console.log(gray(`  unknown command: /${cmd} — try /help`));
  }
  return false; // no continuation needed
}

/* ------------------------------------------------------------------ *
 * Flows (design / operator / newgame) — delegate to bridge
 * ------------------------------------------------------------------ */
function designFlow(idea) {
  if (!idea) {
    console.log(gray("  what should we build? give me the idea, e.g.  design a zombie survival game"));
    return true; // stay in console
  }
  console.log(orange(`  designing: ${idea} — the agent (opencode) takes over; this can take a few minutes.`));
  runBridge(["design", idea]);
  return false;
}

function operatorFlow(task) {
  if (!task) {
    console.log(gray("  what should I change? e.g.  add a double-jump powerup"));
    return true;
  }
  console.log(orange(`  operator: ${task} — the agent edits the runtime; this can take a few minutes.`));
  runBridge(["operator", task]);
  return false;
}

function newgameFlow(idea) {
  if (!idea) {
    console.log(gray("  describe the game, e.g.  new game a fishing RPG"));
    return true;
  }
  console.log(orange(`  new game: ${idea} — deriving the spec now.`));
  runBridge(["newgame", idea]);
  return false;
}

function greet() {
  console.log(orange("  BUILDER BOI online — one prompt, one complete Roblox game."));
  console.log(gray('  Try: "design a zombie survival game"   or   /help'));
}

function unknown(text) {
  console.log(gray(`  didn't catch that — try /help, or just say "design <a game idea>".`));
  console.log(gray(`  (you said: ${text.slice(0, 60)})`));
}

/* ------------------------------------------------------------------ *
 * The console loop
 * ------------------------------------------------------------------ */
function start() {
  const state = loadState();
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: process.stdin.isTTY && process.stdout.isTTY,
  });

  console.log(ascii.banner({ color: USE_COLOR }));
  console.log("");
  console.log(gray("  RBLX Operator — interactive console. Just talk to it, or /help."));

  if (state.firstRun) {
    requestStudioConnect(state);
    state.firstRun = false;
    saveState(state);
  }

  const prompt = () => {
    rl.setPrompt(orange("rblxoperator ❯ ") + RESET);
    rl.prompt();
  };

  rl.on("line", (line) => {
    const { intent, cmd, args } = route(line);
    let stay = false;
    switch (intent) {
      case "empty": stay = true; break;
      case "slash": stay = handleSlash(cmd, args[0] || "", state); break;
      case "design": stay = designFlow(args[0]); break;
      case "operator": stay = operatorFlow(args[0]); break;
      case "newgame": stay = newgameFlow(args[0]); break;
      case "doctor": runBridge(["doctor"]); break;
      case "verify": runBridge(["verify"]); break;
      case "build": runBridge(["build"]); break;
      case "serve": runBridge(["serve"]); break;
      case "studio": requestStudioConnect(state); break;
      case "prompt": runBridge(["prompt"]); break;
      case "banner": console.log(ascii.banner({ color: USE_COLOR })); break;
      case "help": printHelp(); break;
      case "arch": printArch(); break;
      case "greet": greet(); break;
      case "quit": console.log(gray("bye — back to the grid.")); process.exit(0); break;
      default: unknown(line);
    }
    if (stay !== false) prompt();
  });

  rl.on("SIGINT", () => {
    console.log(gray("\nbye — back to the grid."));
    process.exit(0);
  });

  prompt();
}

if (require.main === module) start();
module.exports = { start, route, printHelp, printArch };

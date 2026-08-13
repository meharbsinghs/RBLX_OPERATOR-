#!/usr/bin/env node
"use strict";

/**
 * RBLX Operator — CLI orchestrator.
 *
 * Usage:
 *   rblx                                  # banner + help
 *   rblx banner                           # print the BUILDER BOI ASCII banner
 *   rblx doctor                           # toolchain + environment health check
 *   rblx init                             # scaffold .env, dirs
 *   node pipeline/bridge.js prompt                    # print the master derivation prompt
 *   node pipeline/bridge.js newgame "<idea>"          # prompt -> GameSpec -> config.luau
 *   node pipeline/bridge.js newgame --spec out.json   # import a spec from ANY AI chat
 *   node pipeline/bridge.js newgame --offline "<idea>" # zero-key text derivation
 *   node pipeline/bridge.js asset "<prompt>"          # Meshy 3D asset -> registry (+ Open Cloud upload)
 *   node pipeline/bridge.js verify                    # validate Luau + JS
 *   node pipeline/bridge.js build                     # verify + Rojo build instructions
 *   node pipeline/bridge.js serve                     # live-sync instructions
 *   node pipeline/bridge.js test                      # run the self-simulating Studio test runner
 *   node pipeline/bridge.js fix --log logs/runtime.log   # runtime crash log -> DeepSeek hot-fix
 *   node pipeline/bridge.js design "<idea>"          # end-to-end design loop via the OpenCode engineer
 *   node pipeline/bridge.js newtype "<name>" "<desc>" # scaffold a game-type pack (unbounded genres)
 *   node pipeline/bridge.js plugin                     # print Studio Craft plugin build/install steps
 *   node pipeline/bridge.js operator "<task>"         # engineering loop via the OpenCode engineer
 *   node pipeline/bridge.js smoke ["<idea>"]          # one-command offline end-to-end proof
 *
 * The engine ships the Zombie Rush reference game; every other game is
 * derived from a prompt: the master derivation prompt
 * (pipeline/system_prompt.md) is the design interface — the
 * pipeline sends it to DeepSeek, and you can paste it into ANY AI chat and
 * import the resulting JSON with --spec. The system is built on top of
 * opencode: the rblx-designer agent (.opencode/agents/) is the design brain,
 * the plugin (.opencode/plugins/) arms engine tools, and `design` / `operator`
 * run the end-to-end loop: design -> compile -> verify -> test -> fix.
 */

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const ascii = require("./ascii_banner");
const { which, spawnCli } = require("./clitools");
const codegen = require("./codegen");
const meshy = require("./meshy_client");
const registry = require("./registry");
const { validateLuau } = require("./validate_luau");

// Parses flags in both forms: "--name=value" and "--name value". Returns the
// value and the remaining args with the flag (and its space-form value)
// removed, so consumed values never leak into the prompt text.
function takeFlag(args, name, fallback) {
  const eq = args.find((a) => a.startsWith(`--${name}=`));
  if (eq) {
    return { value: eq.slice(name.length + 3), rest: args.filter((a) => a !== eq) };
  }
  const idx = args.indexOf(`--${name}`);
  if (idx !== -1 && args[idx + 1] && !args[idx + 1].startsWith("--")) {
    return {
      value: args[idx + 1],
      rest: args.filter((a, i) => i !== idx && i !== idx + 1),
    };
  }
  return { value: fallback, rest: args };
}

function loadEnv() {
  const envPath = path.join(ROOT, ".env");
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (match && process.env[match[1]] === undefined) {
      process.env[match[1]] = match[2].replace(/^["']|["']$/g, "");
    }
  }
}

function usage() {
  console.log(`
RBLX Operator — autonomous prompt-to-Roblox-game engine, built on opencode

Commands:
  banner              Print the BUILDER BOI ASCII banner
  doctor              Toolchain + environment health check (opencode, rojo, git, keys)
  init                Scaffold .env and directories
  prompt              Print the master derivation prompt (pipeline/system_prompt.md)
                      — the design interface. Works with ANY AI model.
  newgame "<idea>"    Design a full game spec (DeepSeek or offline) and
                      regenerate src/shared/config.luau
  newgame --spec <file.json>
                      Import a spec designed in any AI chat (see 'prompt')
  newgame --offline "<idea>"
                      Zero-key text derivation (theme/goal aspect hints)
  asset "<prompt>"    Generate a 3D asset via Meshy into assets/generated
                      (auto-uploads to Roblox when OPEN_CLOUD_API_KEY is set)
  props [--sync]      List the spatial prop manifest (assets/props.manifest.json);
                      --sync generates + uploads missing prop models via Meshy+Open Cloud
  verify              Validate all Luau (--!strict, naming, balance) + JS syntax
  build               verify + print Rojo build steps
  serve               print live-sync (rojo serve) steps
  test                Instructions for the self-simulating Studio test runner
  fix --log <file>    Parse a Roblox crash log, let DeepSeek patch the files
  newtype "<name>" "<desc>"
                      Scaffold a game-type pack under gametypes/<slug>/ and
                      register it — the unbounded-genre mechanism (GAME_TYPES.md).
  plugin              Print the Studio Craft plugin build + install steps
  design "<idea>"     End-to-end design loop via the rblx-designer agent (opencode):
                      idea -> spec JSON -> config.luau -> verify gate
  operator "<task>"   Engineering loop via the rblx-designer agent (runtime edits)
  smoke ["<idea>"]    One-command offline end-to-end proof: prompt -> spec ->
                      config -> verify. Zero keys, zero opencode.
`);
}

// Print the BUILDER BOI ASCII banner (from the pre-rendered banner or the
// logo itself). Suppressed for non-TTY (CI) output unless requested.
function printBanner() {
  const saved = path.join(ROOT, "assets", "branding", "banner.txt");
  if (fs.existsSync(saved)) {
    console.log(fs.readFileSync(saved, "utf8"));
  } else {
    console.log(ascii.banner());
  }
}

function cmdBanner() {
  printBanner();
}

function cmdDoctor() {
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok, detail });

  // node
  check("node", true, process.version);

  // opencode CLI + agent + auth
  const ocBin = which("opencode");
  let ocVer = null;
  if (ocBin) {
    try {
      const v = spawnCli(ocBin, ["--version"], { encoding: "utf8", timeout: 15000 });
      if (v.status === 0) ocVer = (v.stdout || "").trim();
    } catch {
      /* ignore */
    }
  }
  check("opencode", Boolean(ocVer), ocVer ? `v${ocVer} (${ocBin})` : "not found — npm i -g opencode-ai");
  if (ocVer) {
    const agentList = spawnCli(ocBin, ["agent", "list"], { encoding: "utf8", timeout: 20000 });
    const hasDesigner = /rblx-designer/.test((agentList.stdout || "") + (agentList.stderr || ""));
    check("rblx-designer agent", hasDesigner, hasDesigner ? "registered (.opencode/agents/)" : "missing — run: opencode agent create");
    const auth = spawnCli(ocBin, ["auth", "list"], { encoding: "utf8", timeout: 20000 });
    const authed = /credentials|●/.test((auth.stdout || "") + (auth.stderr || ""));
    check("opencode auth", authed, authed ? "provider credential found" : "run: opencode auth login");
  }

  // rojo
  const rojoBin = which("rojo");
  const rojo = rojoBin ? spawnCli(rojoBin, ["--version"], { encoding: "utf8", timeout: 15000 }) : null;
  check("rojo", rojo && rojo.status === 0, rojo && rojo.status === 0 ? (rojo.stdout || "").trim().split(/\s+/)[0] : "not found — https://rojo.space (scripts/setup.bat installs it)");

  // git / gh
  const gitBin = which("git");
  const git = gitBin ? spawnCli(gitBin, ["--version"], { encoding: "utf8", timeout: 15000 }) : null;
  check("git", git && git.status === 0, git && git.status === 0 ? (git.stdout || "").trim().split(/\s+/)[0] : "not found — https://git-scm.com");
  const ghBin = which("gh") || (fs.existsSync("C:\\Program Files\\GitHub CLI\\gh.exe") ? "C:\\Program Files\\GitHub CLI\\gh.exe" : null);
  check("gh (GitHub CLI)", Boolean(ghBin), ghBin ? "installed" : "not found — https://cli.github.com");

  // .env keys
  loadEnv();
  const keys = ["DEEPSEEK_API_KEY", "MESHY_API_KEY", "OPEN_CLOUD_API_KEY"].filter((k) => process.env[k]);
  check(".env keys", keys.length > 0, keys.length ? keys.join(", ") : "none set — everything still works offline (newgame --offline)");

  // Roblox Studio
  const studioCandidates = [
    path.join(process.env.LOCALAPPDATA || "", "Roblox", "Versions"),
    "C:\\Program Files (x86)\\Roblox",
  ];
  const studio = studioCandidates.some((p) => { try { return fs.readdirSync(p).length > 0; } catch { return false; } });
  check("Roblox Studio", studio, studio ? "installed" : "not found — install from https://www.roblox.com/create");

  const pad = Math.max(...checks.map((c) => c.name.length));
  console.log("\n[rblx] doctor — toolchain report");
  for (const c of checks) {
    const mark = c.ok ? "✓" : "✗";
    console.log(`  ${mark} ${c.name.padEnd(pad)}  ${c.detail}`);
  }
  console.log("\n[rblx] Next: rblx newgame \"<idea>\"  or  rblx design \"<idea>\" (opencode brain)");
}

function cmdInit() {
  const envPath = path.join(ROOT, ".env");
  if (!fs.existsSync(envPath)) {
    fs.copyFileSync(path.join(ROOT, ".env.example"), envPath);
    console.log("[init] created .env from .env.example — add your DEEPSEEK_API_KEY / MESHY_API_KEY.");
  } else {
    console.log("[init] .env already exists.");
  }
  fs.mkdirSync(path.join(ROOT, "games"), { recursive: true });
  console.log("[init] Ready. Next: node pipeline/bridge.js newgame \"<idea>\"");
}

async function cmdNewGame(args) {
  const spec = takeFlag(args, "spec", null);
  const specFile = spec.value;
  const offline = args.includes("--offline");
  const idea = spec.rest.filter((a) => !a.startsWith("--")).join(" ").trim();
  if (!idea && !specFile) {
    console.error('Usage: node pipeline/bridge.js newgame "a fast-paced zombie survival shooter"');
    console.error('   or: node pipeline/bridge.js newgame --spec mygame.json');
    console.error('   or: node pipeline/bridge.js newgame --offline "futuristic neon arena shooter"');
    process.exit(1);
  }
  if (specFile) {
    console.log(`[newgame] Importing spec: ${specFile}`);
  } else {
    console.log(`[newgame] Deriving from prompt: ${idea}`);
  }
  const designed = await codegen.specFromPrompt(idea, { offline, specFile });
  const result = codegen.writeGameSpec(designed);
  console.log(`[newgame] Wrote ${result.slug}:`);
  console.log(`  spec      -> ${result.specPath}`);
  console.log(`  config    -> ${result.configPath}`);
  console.log(`  weapons=${result.weapons} enemies=${result.enemies} perks=${result.perks} doors=${result.doors} zones=${result.zones}`);
  console.log("[newgame] Next: node pipeline/bridge.js verify, then rojo build.");
}

function cmdPrompt() {
  console.log(codegen.getSystemPrompt());
  console.log("\n---\nThis is the master derivation prompt.");
  console.log("1) The pipeline sends it to DeepSeek when you run `newgame \"<idea>\"`.");
  console.log("2) Paste it as the system prompt of ANY AI chat, describe your game,");
  console.log("   save the JSON it returns, then import it: newgame --spec out.json");
  console.log("3) Edit it to steer the engine's design taste (balance, themes, names).");
}

async function cmdAsset(args) {
  const kind = takeFlag(args, "kind", "prop");
  const prompt = kind.rest.filter((a) => !a.startsWith("--")).join(" ").trim();
  if (!prompt) {
    console.error('Usage: node pipeline/bridge.js asset "low-poly zombie model" --kind=enemy');
    process.exit(1);
  }
  console.log(`[asset] Generating "${prompt}" (kind=${kind.value})...`);
  const record = await meshy.generate3DAsset(prompt, { kind: kind.value });
  const entry = registry.addEntry(record);
  console.log("[asset] Registered in assets/registry.json:");
  console.log(`  id      ${entry.id}`);
  console.log(`  name    ${entry.name}`);
  console.log(`  glb     ${entry.glb || "(none)"}`);
  console.log("  To attach it to a game, mark usage: registry.markUsed in a future bridge command.");
}

function collectJsFiles(dir, acc) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      collectJsFiles(full, acc);
    } else if (name.endsWith(".js")) {
      acc.push(full);
    }
  }
  return acc;
}

// Shared verification gates: Luau (--!strict/naming/blocks) + JS syntax.
// Used by `verify`, `smoke`, and `design`.
function runVerify() {
  const luau = validateLuau({ print: true });
  const jsErrors = [];
  for (const file of collectJsFiles(path.join(ROOT, "pipeline"), [])) {
    const rel = path.relative(ROOT, file).replace(/\\/g, "/");
    try {
      execFileSync(process.execPath, ["--check", file], { stdio: "pipe" });
    } catch (err) {
      jsErrors.push(`${rel}: syntax error`);
    }
  }
  if (jsErrors.length > 0) {
    console.error(`[verify] JS syntax issues: ${jsErrors.join(", ")}`);
  } else {
    console.log("[verify] JS syntax OK.");
  }
  return { luau, jsErrors };
}

function cmdVerify() {
  const { luau, jsErrors } = runVerify();
  if (jsErrors.length > 0) process.exitCode = 1;
  if (!luau.ok) process.exitCode = 1;
  if (process.exitCode === 0) console.log("[verify] All checks passed.");
}

function cmdBuild() {
  cmdVerify();
  console.log(`
[build] To produce a runnable place:
  1. Install Rojo:  https://rojo.space  (scripts/studio.ps1 installs it via Rokit)
  2. rojo build default.project.json -o RBLXOperator.rbxl
  3. Open RBLXOperator.rbxl in Roblox Studio and play.

Live editing:
  rojo serve default.project.json   -> 'Connect' from the Rojo Studio plugin.
`);
}

function cmdServe() {
  console.log(`
[serve] Live-sync your changes into Studio:
  1. Install the Rojo plugin: https://www.roblox.com/library/7168068472/Rojo
  2. Run:  rojo serve default.project.json
  3. In Studio: Plugins -> Rojo -> Connect.
`);
}

function cmdTest() {
  console.log(`
[test] Self-simulating Studio test runner:
  1. In Studio, open a place built from this repo (rojo build default.project.json).
  2. Run the game with testing enabled. Either:
       - set _G.__TESTING = true from a Studio command line script, or
       - set the place attribute "__TESTING" = true, or
       - run: rojo serve default.project.json and inject the flag before Play.
  3. Watch the Output panel: every step prints \"[TEST] PASS|FAIL ...\".
  4. The report is written to logs/runtime_test.log (Studio) so you can run:
       node pipeline/bridge.js fix --log logs/runtime_test.log
  The runner validates the GameSpec, spawns enemies, fires the hitscan engine
  at them, and drives the shop through real purchases.
`);
}

async function cmdProps(args) {
  const opencloud = require("./opencloud");
  const manifest = opencloud.loadPropsManifest();
  const entries = opencloud.listProps(manifest);
  const sync = args.includes("--sync");

  if (entries.length === 0) {
    console.log("[props] Manifest has no placements yet — add entries to assets/props.manifest.json.");
    return;
  }

  console.log(`\n[props] Spatial prop manifest — ${entries.length} hand-placed props:`);
  for (const entry of entries) {
    const pos = entry.position.length ? `[${entry.position.join(", ")}]` : "(no position)";
    const status = entry.rbxassetId ? entry.rbxassetId : entry.model ? "(model pending upload)" : "(visual prop)";
    console.log(`  ${entry.group.padEnd(13)} ${entry.id.padEnd(6)} @ ${pos}  ${entry.model ? `model=${entry.model}  ` : ""}${status}`);
  }
  console.log("\n  Tip: `node pipeline/bridge.js props --sync` generates + uploads missing models");
  console.log("       (requires MESHY_API_KEY + OPEN_CLOUD_API_KEY in .env).");

  if (sync) {
    // Dedupe by model name: several placements share one prop model (e.g. four
    // wall-weapon mounts) — generate once, assign the same upload to all.
    const byModel = new Map();
    for (const entry of entries) {
      if (entry.model && !entry.rbxassetId) {
        if (!byModel.has(entry.model)) byModel.set(entry.model, []);
        byModel.get(entry.model).push(entry);
      }
    }
    if (byModel.size === 0) {
      console.log("[props] --sync: all props already have uploaded models.");
      return;
    }
    if (!process.env.MESHY_API_KEY) {
      console.error("[props] --sync requires MESHY_API_KEY in .env (Meshy text-to-3D).");
      process.exit(1);
    }
    for (const [model, placements] of byModel) {
      console.log(`[props] Generating "${model}" for ${placements.map((p) => p.id).join(", ")}...`);
      try {
        const record = await meshy.generate3DAsset(`${model} prop asset for a Roblox map: ${model.replace(/-/g, " ")}`, {
          kind: "prop",
          name: model,
        });
        if (record.rbxassetId) {
          for (const entry of placements) {
            opencloud.setPropAssetId(manifest, entry.group, entry.id, record.rbxassetId);
          }
          console.log(`  -> uploaded: ${record.rbxassetId}`);
        } else {
          console.warn(`  -> generated ${record.glb} but upload skipped (no OPEN_CLOUD_API_KEY).`);
        }
      } catch (err) {
        console.warn(`  -> failed: ${err.message}`);
      }
    }
    opencloud.savePropsManifest(manifest);
    console.log("[props] Manifest updated with uploaded asset ids.");
  }
}

async function cmdFix(args) {
  const log = takeFlag(args, "log", "logs/runtime.log");
  const logPath = log.value;
  const dryRun = args.includes("--dry-run");
  const autofix = require("./autofix");
  if (!fs.existsSync(logPath)) {
    console.error(`[fix] Log not found: ${logPath}`);
    console.error("      Copy a Roblox output/crash log there, or pass --log=<path>.");
    process.exit(1);
  }
  console.log(`[fix] Parsing ${logPath}${dryRun ? " (dry-run)" : ""}...`);
  const result = await autofix.autofixLog(logPath, { dryRun });
  console.log(`[fix] ${result.errors} error(s) across ${result.files} file(s); fixed ${result.fixed}.`);
  if (result.unfixed.length > 0) {
    console.log(`[fix] Still open: ${result.unfixed.join(", ")}`);
  }
  if (result.fixed > 0 && !dryRun) {
    console.log("[fix] Rebuild with: rojo build default.project.json -o RBLXOperator.rbxl");
  }
}

async function cmdOperator(args) {
  const task = args.filter((a) => !a.startsWith("--")).join(" ").trim();
  if (!task) {
    console.error('Usage: node pipeline/bridge.js operator "refactor the shop module into two files"');
    process.exit(1);
  }
  const opencode = require("./operators/opencode_operator");
  if (!opencode.isAvailable()) {
    console.error("[operator] " + opencode.guidance());
    process.exit(1);
  }
  const model = process.env.OPENCODE_MODEL || undefined;
  const agent = process.env.OPENCODE_AGENT || "rblx-designer";
  console.log(`[operator] opencode running: ${task}`);
  console.log(`[operator] model=${model || "default"} agent=${agent} cwd=${opencode.ROOT}`);
  const res = opencode.runTask(task, { model, agent });
  if (res.status !== 0) {
    console.error(`[operator] OpenCode exited ${res.status}`);
    if (res.stderr) console.error(res.stderr.slice(0, 4000));
    process.exitCode = 1;
  }
  if (res.stdout) console.log(res.stdout.slice(0, 20000));
}

async function cmdDesign(args) {
  const idea = args.filter((a) => !a.startsWith("--")).join(" ").trim();
  if (!idea) {
    console.error('Usage: node pipeline/bridge.js design "a neon extraction shooter set on a derelict space station"');
    process.exit(1);
  }
  const opencode = require("./operators/opencode_operator");
  if (!opencode.isAvailable()) {
    console.error("[design] " + opencode.guidance());
    process.exit(1);
  }
  const model = process.env.OPENCODE_MODEL || undefined;
  const agent = process.env.OPENCODE_AGENT || "rblx-designer";
  console.log(`[design] rblx-designer (opencode) designing: ${idea}`);
  console.log(`[design] model=${model || "default"} agent=${agent} — this can take a few minutes.`);
  const report = await opencode.designGame(idea, { model, agent });
  console.log("\n--- engineer report ---");
  console.log(report.log);
  if (!report.ok) {
    console.error("[design] FAILED — see report above.\n");
    if (report.verify && report.verify.issues.length > 0) {
      console.error("[design] Luau gate:");
      for (const issue of report.verify.issues) console.error(`  ✗ ${issue}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log("\n[design] PASS — end-to-end design loop complete:");
  console.log(`  spec      -> ${report.specFile}`);
  console.log(`  config    -> ${report.configFile}`);
  console.log(`  weapons=${report.weapons} enemies=${report.enemies} perks=${report.perks} doors=${report.doors} zones=${report.zones}`);
  console.log("[design] Next: node pipeline/bridge.js verify, then rojo build default.project.json.");
}

// Scaffold a new game-type pack: gametypes/<slug>/ + registry entry. This is
// the unbounded-genre mechanism (see GAME_TYPES.md) — the Operator fills the
// runtime pack; the design prompt and the Studio plugin then know the type.
async function cmdNewtype(args) {
  const name = (args.filter((a) => !a.startsWith("--"))[0] || "").trim();
  const description = args.filter((a) => !a.startsWith("--")).slice(1).join(" ").trim() || "New game type";
  if (!name) {
    console.error('Usage: node pipeline/bridge.js newtype "Obby" "obstacle course platformer: jump, climb, reach the end"');
    process.exit(1);
  }
  const slug = codegen.slugify(name);
  const dir = path.join(ROOT, "gametypes", slug);
  if (fs.existsSync(dir)) {
    console.error(`[newtype] ${slug} already exists in gametypes/${slug}/`);
    process.exit(1);
  }
  fs.mkdirSync(path.join(dir, "runtime"), { recursive: true });

  fs.writeFileSync(
    path.join(dir, "spec.fragment.json"),
    JSON.stringify(
      {
        gameType: slug,
        name: name,
        tagline: "",
        // This genre's schema — the fields the runtime pack reads. Extend
        // freely; the pipeline clamps numbers and sanitizes colors.
      },
      null,
      2
    ) + "\n"
  );

  fs.writeFileSync(
    path.join(dir, "README.md"),
    [
      `# ${name} — game type pack`,
      "",
      description,
      "",
      "## Design contract",
      "- The runtime pack lives in `runtime/` — typed Luau modules, read ONLY",
      "  from the GameSpec (src/shared/config.luau), never hardcoded games.",
      "- Register every remote/tag/folder/attribute in src/shared/constants.luau.",
      "- Bootstrap from src/server/init.server.luau (or dispatch on config.gameType).",
      "- Every file starts with --!strict; finish with: node pipeline/bridge.js verify",
      "",
      "## How to build it (Operator session)",
      `  node pipeline/bridge.js operator \"implement the ${slug} runtime pack: ` +
        `read the spec schema from spec.fragment.json, wire remotes in constants.luau, ` +
        `bootstrap from init.server.luau. --!strict, verify before done.\"`,
      "",
      "Then design games of this type with newgame --spec (any AI chat) and",
      "playtest through the Studio Craft plugin.",
      "",
      "See GAME_TYPES.md for the full mechanism.",
    ].join("\n") + "\n"
  );

  const registryPath = path.join(ROOT, "gametypes", "registry.json");
  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  registry[slug] = {
    name,
    status: "scaffold",
    runtime: `gametypes/${slug}/runtime (Operator-authored)`,
    description,
    spec: "newtype scaffold — Operator fills the runtime + schema",
  };
  fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2) + "\n");

  console.log(`[newtype] Scaffolded game-type pack: ${name}`);
  console.log(`  gametypes/${slug}/README.md`);
  console.log(`  gametypes/${slug}/spec.fragment.json`);
  console.log(`  gametypes/${slug}/runtime/   (Operator fills this)`);
  console.log(`[newtype] Registered '${slug}' in gametypes/registry.json — the design`);
  console.log(`          prompt + Studio Craft plugin now know this type exists.`);
  console.log(`[newtype] Next: bridge.js operator \"implement the ${slug} runtime pack…\"`);
}

function cmdPlugin() {
  console.log(`
[plugin] RBLX Operator Craft — the Studio playtest & craft surface.

Build + install (one command, needs Rojo once):
  scripts\\plugin.ps1

Manual:
  rojo build plugin/plugin.project.json -o "%LOCALAPPDATA%\\Roblox\\Plugins\\RBLXOperatorCraft.rbxmx"
  then restart Roblox Studio and use the 'RBLX Operator' toolbar button.

Tabs: CONSOLE (live devlog) · PLAYTEST (one-click) · CRAFT (lighting moods,
GameSpec mood, Meshy/Open Cloud asset injector) · SPEC (derived game identity).
Docs: plugin/README.md
`);
}

async function cmdSmoke(args) {
  const idea =
    args.filter((a) => !a.startsWith("--")).join(" ").trim() ||
    "futuristic neon alien wave shooter — the grid is infected, purge it in neon";
  console.log(`[smoke] End-to-end offline proof — deriving from: ${idea}`);
  const spec = await codegen.specFromPrompt(idea, { offline: true });
  const result = codegen.writeGameSpec(spec);
  console.log(`[smoke] Compiled ${result.slug}: weapons=${result.weapons} enemies=${result.enemies} doors=${result.doors} zones=${result.zones}`);
  const { luau, jsErrors } = runVerify();
  const pass = luau.ok && jsErrors.length === 0;
  if (pass) {
    console.log("[smoke] PASS — prompt -> spec -> config.luau -> verify, end to end.");
  } else {
    console.error("[smoke] FAIL — see issues above.");
    process.exitCode = 1;
  }
}

async function main() {
  loadEnv();
  const quiet = process.argv.includes("--quiet");
  const [cmd, ...args] = process.argv.slice(2);
  if (!quiet && process.stdout.isTTY && cmd && cmd !== "banner") {
    printBanner();
  }
  switch (cmd) {
    case undefined: printBanner(); usage(); break;
    case "banner": cmdBanner(); break;
    case "doctor": cmdDoctor(); break;
    case "init": cmdInit(); break;
    case "newgame": await cmdNewGame(args); break;
    case "asset": await cmdAsset(args); break;
    case "props": await cmdProps(args); break;
    case "verify": cmdVerify(); break;
    case "build": cmdBuild(); break;
    case "serve": cmdServe(); break;
    case "prompt": cmdPrompt(); break;
    case "newtype": cmdNewtype(args); break;
    case "plugin": cmdPlugin(); break;
    case "test": cmdTest(); break;
    case "fix": await cmdFix(args); break;
    case "operator": await cmdOperator(args); break;
    case "design": await cmdDesign(args); break;
    case "smoke": await cmdSmoke(args); break;
    default: usage();
  }
}

main().catch((err) => {
  console.error(`[bridge] ${err.stack || err.message}`);
  process.exit(1);
});

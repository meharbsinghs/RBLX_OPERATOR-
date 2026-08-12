# 🎮 RBLX OPERATOR

**A free, open-source engine that derives complete, balanced, playable Roblox
games from a prompt.** It ships **no games** — you design them by describing
them. Describe a game idea; get a real, typed, commercially-balanced Roblox
game — real systems, real economy, real UI, real lighting, real sound — buildable
and playable in minutes. **Free.** No subscriptions. Clone, run, derive.

> **Website:** https://meharbsinghs.github.io/RBLX_OPERATOR- · **Desktop app
> (.exe):** build via GitHub Actions on every push (see *Downloads* below).

The core idea is a separation that AI game-dev has never had:

- **The engine is fixed and generic.** A hand-built, typed, server-authoritative
  Luau runtime that can play an enormous range of action games. It ships once,
  is validated, and never changes per game.
- **The design is data.** A `GameSpec` (`src/shared/config.luau`) is the whole
  game — balance, rosters, economy, map, lighting, UI theme, and a **craft
  layer** (sound identity, atmosphere, story hooks). The runtime renders
  whatever it says.
- **The derivation is a prompt.** `pipeline/system_prompt.md` is the master
  derivation prompt: it turns any game idea into a complete `GameSpec`, via
  DeepSeek, Freebuff (free), *or any AI model you already use*.
- **The ceiling is not bounded.** The engine ships the action-shooter family
  today (wave / extraction / defense / arena / boss-rush), and `bridge.js
  newtype` scaffolds **game-type packs** so the Operator can extend the runtime
  to *any* genre — obbies, tycoons, racing, RPGs — with the Studio Craft
  plugin as the delivery and playtest surface. See `GAME_TYPES.md`.

Swap the spec, get a different game. **The prompt is the interface.**

---

## Quickstart (60 seconds, zero keys)

```bash
# 1. Clone this repo and open a terminal inside it

# 2. (Optional) install Rojo once:  https://rojo.space   (or: run scripts\setup.bat, choice 2)

# 3. Build the game file
rojo build default.project.json -o RBLXOperator.rbxl

# 4. Open RBLXOperator.rbxl in Roblox Studio and press Play
```

That's the engine's **reference game** (a full round-based survival shooter —
the benchmark for everything derived after it). Now derive your own:

```bash
node pipeline/bridge.js newgame "a tense extraction shooter: raid the harbor,
loot the vault, extract by wave 5 or die trying"
rojo build default.project.json -o RBLXOperator.rbxl
```

New game. Same engine. One prompt.

No keys are required to run or build anything — maps, enemies, weapons, UI,
lighting and audio are all procedural and data-driven.

---

## One-click setup (Windows)

No terminal skills needed — double-click and go:

```bat
scripts\setup.bat
```

It offers to install Node.js if it's missing, runs the verify gate, then gives
you three choices:

1. **Push to GitHub** — installs Git + the GitHub CLI if missing, **links your
   GitHub account** (a browser opens with a one-time code), runs the verify
   gate, creates the repo and pushes (`scripts/push.ps1`).
2. **Add to Studio** — installs Rojo via Rokit if missing, builds
   `RBLXOperator.rbxl`, and prints the live-sync + Open Cloud upload steps
   (`scripts/studio.ps1`).
3. **Open the desktop app** — launches the built `RBLX Operator` .exe.

All paths are safe by default: `.env` is gitignored and the push script
double-checks no secrets would be committed before it pushes.

---

## Desktop app (.exe) — no terminal needed

The whole system also ships as a Windows desktop app: **RBLX Operator Studio**.
Users need **nothing installed except Roblox Studio** — the app bundles the
engine *and* its Node runtime, so there is no terminal and no Node.js to
install:

- **Design** — type a game idea, pick a mode (Operator engineer / DeepSeek /
  offline / import a spec from any AI chat), press **Generate Game**.
- **Verify** — run the full Luau + JS gate, or the end-to-end `smoke` proof.
- **Build & open** — one click builds `RBLXOperator.rbxl` and opens it in
  Roblox Studio.
- **Publish** — one click links your GitHub account, creates the repo and
  pushes; CI then builds the next `.exe` automatically.

**Getting the .exe (free):**

| Route | How |
|---|---|
| **GitHub Actions** | Every push runs the *Build EXE* workflow → Actions tab → newest run → *Artifacts* → `rblx-operator-windows` |
| **GitHub Release** | Tag a commit (`git tag v1.0.0 && git push --tags`) and the installer + portable .exe are attached to the Release page |
| **Build locally** | `npm run app:install` then `npm run app:build` → `app/dist/` |
| **Run from source** | `npm run app:start` (operates on the repo itself) |

The installed app keeps its own workspace copy of the engine at
`%APPDATA%\RBLX Operator\workspace` — games, `.env` keys and logs all live
there; the shipped files are never modified.

---

## The website (GitHub Pages)

The repo deploys a landing site to GitHub Pages on every push to `main`:
`site/` (pure HTML/CSS/JS, zero build step) + `.github/workflows/deploy-site.yml`.
It ships the BUILDERBOI mark as the RBLX Operator mascot, the pipeline
explainer, the game-type roadmap, and download links. It goes live at:

```
https://meharbsinghs.github.io/RBLX_OPERATOR-/
```

---

## The Studio Craft plugin

`plugin/` contains the **RBLX Operator Craft** plugin — the playtest and craft
surface inside Roblox Studio:

- **Console** — live devlog streamed from the running engine (rounds, spawns,
  economy, shop, tests) so a playtest session is fully observable.
- **Playtest** — one-click start of a local test run (`TestService`).
- **Craft** — lighting mood presets (dusk / night / neon / day) and **Apply
  GameSpec mood**, which reads the derived game's lighting profile and paints
  it into Studio before you press Play; plus a **Meshy/Open Cloud asset
  injector** that drops an `rbxassetid://` model into the place at your mouse.
- **Spec** — the derived game's identity (name, game type, rosters, win
  condition) at a glance.

Build + install it (needs Rojo once):

```bat
scripts\plugin.ps1
```

or manually: `rojo build plugin/plugin.project.json -o
%LOCALAPPDATA%\Roblox\Plugins\RBLXOperatorCraft.rbxmx` and restart Studio.

---

## Derive any game — the four routes

| Route | Command | When |
|---|---|---|
| **DeepSeek / Freebuff** (novel design) | `newgame "<idea>"` with a `DEEPSEEK_API_KEY` | You want a fully designed game from your words |
| **Any AI chat** (no key needed) | `bridge.js prompt` → paste prompt as system prompt → save JSON → `newgame --spec out.json` | You already use Claude / ChatGPT / Gemini / Freebuff |
| **Offline** (zero keys, instant) | `newgame --offline "<idea>"` | Prototyping; theme/goal hints off the reference spec |
| **Human** | Edit `games/<slug>/spec.json` by hand | Total control — the spec is plain data |

The **master derivation prompt** (`pipeline/system_prompt.md`) is the product's
design interface. It teaches any model the engine's quality bar (commercial
polish, **Michael's Zombies / CoD Zombies caliber**), the exact schema, and the
derivation method: *goal → round structure* (endless survival vs. extraction
`winRound` vs. defense vs. arena), *theme → art direction + lighting + UI
tokens + sound identity*, *roster design*, *economy pacing*, *map layout*.

**Example briefs** (the inputs, not outputs): `examples/prompts/` — zombies,
extraction, tower defense, neon arena. Each one derives a radically different
game from the same engine.

---

## CLI

```
node pipeline/bridge.js init                        # scaffold .env + directories
node pipeline/bridge.js prompt                      # print the master derivation prompt
node pipeline/bridge.js newgame "<idea>"            # design a full game (DeepSeek)
node pipeline/bridge.js newgame --spec <file.json>  # import a design from any AI chat
node pipeline/bridge.js newgame --offline "<idea>"  # zero-key text derivation
node pipeline/bridge.js asset "<prompt>"            # Meshy text-to-3D → registry (+ Roblox upload)
node pipeline/bridge.js props [--sync]              # spatial prop manifest (generate + upload models)
node pipeline/bridge.js newtype "<name>" "<desc>"   # scaffold a game-type pack (unbounded genres)
node pipeline/bridge.js verify                      # validate all Luau + JS
node pipeline/bridge.js build / serve               # Rojo build / live-sync steps
node pipeline/bridge.js plugin                      # print Studio Craft plugin build/install steps
node pipeline/bridge.js test                        # run the self-simulating Studio test runner
node pipeline/bridge.js fix --log logs/runtime.log  # crash log → AI hot-fix
node pipeline/bridge.js design "<idea>"             # end-to-end design loop (Operator engineer)
node pipeline/bridge.js operator "<task>"           # engineering loop: runtime edits (Operator)
node pipeline/bridge.js smoke ["<idea>"]            # one-command offline end-to-end proof
```

---

## The orchestration stack

This system is built to be **orchestrated** — one brain commands a crew of
specialists, all free:

| Role | Who | What it does |
|---|---|---|
| **Orchestrator** | **Buffy (Freebuff)** | Commands the whole pipeline: plans the game, dispatches designers and engineers, verifies, pushes to GitHub, runs the release loop |
| **Operator** | OpenCode CLI (`operators/`) | The in-repo engineering brain: derives GameSpecs end-to-end (`design`), edits the runtime itself (`operator`), hot-fixes crash logs (`fix`) |
| **Design brain** | DeepSeek (via Freebuff) | Turns a prompt into a complete, balanced GameSpec JSON (`newgame`) |
| **Art director** | Meshy AI | Text-to-3D assets for maps, enemies and props (`asset`, `props --sync`) |
| **Asset host** | Roblox Open Cloud | Auto-uploads generated models and returns live `rbxassetid://` links |
| **Quality gate** | `validate_luau.js` + test runner | `--!strict`, naming, block balance, JS syntax, self-simulating Studio tests |

The loop the Operator drives is the whole system in miniature:

```
idea ──► design ──► compile ──► gate ──► test ──► fix ──► iterate
 │        │           │          │         │        │
 │   Operator     codegen    bridge.js   testrunner  autofix.js
 │   derives    emits typed    verify    __TESTING   parses crash
 │   the spec    config.luau   (Luau+JS)  in Studio   logs → patch
 └──── user's words become a game; failures feed back in
```

- **`design "<idea>"`** — end to end in one command: Operator derives the
  GameSpec JSON, the pipeline compiles it into `src/shared/config.luau`, and
  the Luau gate runs.
- **`operator "<task>"`** — the engineering loop: new systems, refactors, and
  fixes to the runtime itself, under a persona that keeps it generic
  (spec-driven, `--!strict`, remotes registered in `constants.luau`, verify
  before done).
- **`fix --log`** — the runtime feedback loop: playtest crashes and test-runner
  failures are parsed, mapped back to repo files, and hot-patched.
- **`newtype "<name>" "<desc>"`** — scaffolds a new game-type pack
  (`gametypes/<slug>/`) so the engine can be extended to *any* genre; the
  design prompt then knows the type exists. See `GAME_TYPES.md`.

---

## What's inside

| Layer | What it is |
|---|---|
| **`pipeline/`** (Node, zero deps) | CLI + **master derivation prompt** (`system_prompt.md`) + DeepSeek designer (JSON-validated) + Meshy 3D client + **Roblox Open Cloud auto-upload** + **runtime-crash hot-fix loop** + **Operator game-design engineer** (`operators/`: persona + end-to-end design loop + verify gate) + **game-type scaffolder** (`newtype`) + Luau validator + **logo→icon builder** (`build_icon.js`) |
| **`src/shared/config.luau`** | **The GameSpec** — game type, rounds, enemies, weapons, perks, economy, doors, map, lighting profile, style guide, anti-cheat tuning, UI theme tokens, audio identity. Generated from your prompt; hand-editable. |
| **`src/server/`** (Luau) | Generic authoritative engine: procedural map + nav graph + dynamic lighting + atmosphere, enemy AI & scaling, round state machine (with objective wins), server-authoritative hitscan + **anti-cheat**, economy + persistence, shop (doors / wall buys / mystery box / pack-a-punch / perks / barricade repair), **audio director** (music tension layers + SFX), **devlog** (every system event, streamed to the Craft plugin), **compressed batched networking** with death events, **self-simulating test runner** |
| **`src/client/`** (Luau) | Real UI framework (`uikit`: theme tokens, gradients, CanvasGroups, rotating 3D viewport previews), data-driven HUD, FPS camera + **spring-physics viewmodel** (sway/kick/ADS/reload/bob), **entity interpolation + local death VFX** (blood bursts & ragdolls) |
| **`plugin/`** | **RBLX Operator Craft** — Studio plugin: live devlog console, one-click playtest, lighting mood presets, GameSpec mood preview, Meshy/Open Cloud asset injector, spec inspector |
| **`site/`** | GitHub Pages landing site (pure HTML/CSS/JS) |
| **`gametypes/`** | Game-type registry + packs — the unbounded-genre mechanism (see `GAME_TYPES.md`) |
| **`assets/`** | **Branding** (BUILDERBOI logo → `icon.ico`, `logo-256.png`), generated models + registry, **spatial prop manifest** (`props.manifest.json`) |
| **`docs/`** | **`WHITEPAPER.md`** (architecture) · **`USER_MANUAL.md`** (full guide incl. GitHub push) · **`ORCHESTRATION.md`** (the crew + how to command it) |
| **`examples/prompts/`** | Example derivation briefs — the inputs, not shipped games |

## Design decisions worth knowing

- **The game is data; the engine is generic.** Every system reads
  `config.luau` — including lighting, materials, UI colors and audio. One
  prompt re-themes the world, the HUD *and* the soundtrack with zero code
  changes.
- **No NavMesh required.** Enemy pathing uses a waypoint graph (zone centers +
  door nodes) with line-of-sight shortcuts and barricade targeting — works on
  any runtime-generated map.
- **Server-authoritative everything.** Fire rate, ammo, raycast, damage and
  points are validated server-side; **anti-cheat** samples movement
  (teleport/speed-hack → snap-back or kick), rejects impossible shot origins,
  and probes for wall-clips.
- **Bandwidth-conscious networking.** Hot enemy state rides one compressed
  batch remote (`EnemyStateBatch`, integer keys via `pack.luau`) at
  `config.net.enemyBatchHz`; clients smooth locally. Kills ride the same
  channel as **death events**, spawning local blood bursts + ragdoll physics
  with zero extra traffic.
- **Weighty weapon feel.** `viewmodel.luau` drives the first-person weapon with
  damped springs: sway, kick scaled by the weapon's `recoil` stat, ADS blend,
  reload dip, walk bob. Feel is data.
- **Craft is data too.** The `audio` block gives every game a sound identity
  (ambience, a music tension curve per round state, signature SFX); the
  `map.theme.lighting` profile paints mood; the `theme` block flips the whole
  UI. Missing audio ids degrade to silence, never crashes.
- **Hand-placed props, not math.** `assets/props.manifest.json` pins complex
  props to explicit coordinates; the pipeline can generate and upload their
  models automatically (Meshy + Open Cloud).
- **Structured-output validation.** Designer JSON is shape-checked and every
  number clamped before it becomes `--!strict` Luau; a hallucinated comma
  degrades to defaults, never a crash.
- **Automated testing.** `_G.__TESTING = true` boots a self-simulating runner:
  validates the spec, spawns rounds, fires the hitscan engine, drives the shop —
  machine-parseable `[TEST] PASS|FAIL` → `logs/runtime_test.log` → hot-fix loop.
- **`--!strict` everywhere.** Every `.luau` is typed against `types.luau`; CI
  (`node pipeline/bridge.js verify`) enforces it on every push.
- **Free-tier friendly.** Zero keys run everything. DeepSeek (design), Meshy
  (assets), Open Cloud (uploads) and Operator (agent ops) are drop-in
  upgrades; every failure path degrades gracefully.

## Conventions

- Every Luau file starts with `--!strict`. Boot scripts: `init.server.luau` /
  `init.client.luau`; everything else is a ModuleScript (`.luau`).
- All remotes/tags/folders/attributes are declared in `src/shared/constants.luau`.
- Run `node pipeline/bridge.js verify` after editing Luau, and before
  `rojo build`.
- **Never commit `.env`** (gitignored — your keys stay local). Full push guide
  in `docs/USER_MANUAL.md` §9.

## Docs

- **`docs/USER_MANUAL.md`** — quickstart, all four derivation routes, keys,
  Studio workflow, testing, hot-fix loop, GitHub publishing, FAQ.
- **`docs/WHITEPAPER.md`** — the architecture paper: why AI can't ship games,
  the game-is-data contract, the derivation pipeline, runtime design, threat
  model, economics.
- **`docs/ORCHESTRATION.md`** — the crew (Buffy / Operator / DeepSeek / Meshy),
  how to command them, and how the release loop runs.
- **`GAME_TYPES.md`** — the unbounded-genre mechanism: what ships, what
  `newtype` scaffolds, and how Operator extends the runtime to any game.
- **`examples/prompts/`** — example derivation briefs that exercise the full
  range: zombies, extraction, tower defense, neon arena.

## Credits

Built and orchestrated by **Buffy (Freebuff)** — commanded by the owner of this
repo — with **Operator (OpenCode)** as the in-repo engineering brain, **DeepSeek**
as the design brain, and **Meshy AI** + **Roblox Open Cloud** for art direction.
See `AUTHORS.md`.

MIT licensed. Build something great.

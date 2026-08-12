<p align="center">
  <img src="assets/branding/logo-256.png" alt="RBLX Operator" width="140" />
</p>

<h1 align="center">🎮 RBLX OPERATOR</h1>

<p align="center">
  <b>One prompt. One complete, balanced, playable Roblox game.</b><br />
  Real economy · real lighting · real sound · real systems — not placeholders.<br />
  Free &amp; open source (MIT). Windows desktop app included.
</p>

<p align="center">
  <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/meharbsinghs/RBLX_OPERATOR-?label=release&style=flat-square" /></a>
  <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/meharbsinghs/RBLX_OPERATOR-/ci.yml?label=verify&style=flat-square" /></a>
  <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/actions/workflows/build-exe.yml"><img alt="Build EXE" src="https://img.shields.io/github/actions/workflow/status/meharbsinghs/RBLX_OPERATOR-/build-exe.yml?label=windows+build&style=flat-square" /></a>
  <a href="https://meharbsinghs.github.io/RBLX_OPERATOR-/"><img alt="Website" src="https://img.shields.io/badge/website-live-orange?style=flat-square" /></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=flat-square" /></a>
</p>

<p align="center">
  <b>⬇️ Download for Windows</b><br />
  <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/releases/latest/download/rblx-operator-setup.exe">Installer (.exe)</a>
  · <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/releases/latest/download/rblx-operator-portable.exe">Portable (.exe)</a>
  · <a href="https://github.com/meharbsinghs/RBLX_OPERATOR-/blob/main/plugin/RBLXOperatorCraft.luau">Studio Craft plugin</a>
</p>

---

## What it is

**RBLX Operator ships complete Roblox games from a single prompt.** Describe a
game in one sentence — *"a tense zombie survival in a cursed mall, 10 waves"* —
and the pipeline designs, compiles, verifies and builds a **full game**: a
procedural map with waypoint AI, server-authoritative combat and anti-cheat, a
balanced points economy (doors, perks, mystery box, pack-a-punch), escalating
enemy waves with bosses, a spring-physics weapon feel, a lighting mood, a sound
identity, and a themed UI — ready to press Play on in Roblox Studio.

This isn't a template or a reskin. Every game is a typed, validated
`GameSpec` rendered by a fixed, hand-built, `--!strict` Luau runtime — the same
separation commercial studios use: **engine once, games forever.**

- **Website:** https://meharbsinghs.github.io/RBLX_OPERATOR-
- **Docs:** `docs/USER_MANUAL.md` · `docs/WHITEPAPER.md` · `docs/ORCHESTRATION.md`
- **Zero keys required** to design offline — DeepSeek, Meshy and Open Cloud are optional upgrades.

---

## ⚡ Quickstart (60 seconds)

```bash
# 1. Clone this repo
git clone https://github.com/meharbsinghs/RBLX_OPERATOR-.git

# 2. (Windows, no terminal skills) double-click:
scripts\setup.bat          # installs Node, verifies, links GitHub, opens the app

# 3. Or straight from a terminal:
node pipeline/bridge.js newgame "a zombie survival in a cursed mall, 10 waves"
rojo build default.project.json -o RBLXOperator.rbxl
# 4. Open RBLXOperator.rbxl in Roblox Studio → press Play
```

That's the engine's **reference game** (a full round-based survival shooter —
the benchmark for everything derived after it). One prompt → one new game.
Same engine. **New game every time.**

---

## 🖥️ The desktop app (.exe) — no terminal, no Node

**RBLX Operator Studio** bundles the engine *and* its Node runtime. Users only
need Roblox Studio. Everything in one console:

- **Design** — type a game idea, pick a mode (Operator engineer / DeepSeek /
  offline / import a spec from any AI chat) → **Generate Game**.
- **Verify** — full Luau + JS gate, or the end-to-end `smoke` proof.
- **Build & open** — one click builds `RBLXOperator.rbxl` and opens it in
  Roblox Studio.
- **Publish** — one click links your GitHub account, creates a repo and pushes;
  CI then builds the next `.exe` automatically.

| Route | How |
|---|---|
| **Installer** | [`rblx-operator-setup.exe`](https://github.com/meharbsinghs/RBLX_OPERATOR-/releases/latest/download/rblx-operator-setup.exe) — always the newest build |
| **Portable** | [`rblx-operator-portable.exe`](https://github.com/meharbsinghs/RBLX_OPERATOR-/releases/latest/download/rblx-operator-portable.exe) — no install |
| **Versioned** | [Releases page](https://github.com/meharbsinghs/RBLX_OPERATOR-/releases) — tag `v1.0.0` style |
| **Build locally** | `npm run app:install` → `npm run app:build` → `app/dist/` |

---

## 🧩 The Studio Craft plugin

Inside Roblox Studio, `plugin/RBLXOperatorCraft.luau` is the playtest + craft
surface:

- **Console** — live devlog streamed from the running engine (rounds, spawns,
  economy, shop, tests).
- **Playtest** — one-click local test run (`TestService`).
- **Craft** — lighting mood presets (dusk / night / neon / day) and **Apply
  GameSpec mood**, which paints the derived game's lighting into Studio before
  you press Play; plus a **Meshy/Open Cloud asset injector**.
- **Spec** — the derived game's identity at a glance.

```bat
scripts\plugin.ps1    # installs it (needs Rojo once)
```

---

## 🎨 Design any game — four routes

| Route | Command | When |
|---|---|---|
| **DeepSeek / Freebuff** | `newgame "<idea>"` with a `DEEPSEEK_API_KEY` | A fully designed game from your words |
| **Any AI chat** (no key) | `bridge.js prompt` → paste as system prompt → save JSON → `newgame --spec out.json` | You already use Claude / ChatGPT / Gemini / Freebuff |
| **Offline** (zero keys) | `newgame --offline "<idea>"` | Prototyping; theme/goal hints off the reference spec |
| **Human** | Edit `games/<slug>/spec.json` by hand | Total control — the spec is plain data |

The **master derivation prompt** (`pipeline/system_prompt.md`) is the product's
design interface: it teaches any model the quality bar (commercial polish,
**Michael's Zombies / CoD Zombies caliber**), the exact schema, and the
derivation method — *goal → round structure*, *theme → art direction +
lighting + UI tokens + sound identity*, *roster design*, *economy pacing*,
*map layout*.

---

## ♾️ No bounded ceiling

The engine ships the **action-shooter family** today (`wave`, `extraction`,
`defense`, `arena`, `boss-rush`) — and `bridge.js newtype` scaffolds
**game-type packs** so the Operator can extend the runtime to *any* genre:
obbies, tycoons, racing, RPGs. Each pack is typed Luau + a spec schema,
delivered and playtested through the Craft plugin. See `GAME_TYPES.md`.

---

## 🛠️ CLI

```
node pipeline/bridge.js init                        # scaffold .env + directories
node pipeline/bridge.js prompt                      # print the master derivation prompt
node pipeline/bridge.js newgame "<idea>"            # design a full game (DeepSeek)
node pipeline/bridge.js newgame --spec <file.json>  # import a design from any AI chat
node pipeline/bridge.js newgame --offline "<idea>"  # zero-key text derivation
node pipeline/bridge.js asset "<prompt>"            # Meshy text-to-3D → registry (+ upload)
node pipeline/bridge.js props [--sync]              # spatial prop manifest (generate + upload)
node pipeline/bridge.js newtype "<name>" "<desc>"   # scaffold a game-type pack (unbounded genres)
node pipeline/bridge.js verify                      # validate all Luau + JS
node pipeline/bridge.js build / serve               # Rojo build / live-sync steps
node pipeline/bridge.js plugin                      # Studio Craft plugin build/install steps
node pipeline/bridge.js test                        # self-simulating Studio test runner
node pipeline/bridge.js fix --log logs/runtime.log  # crash log → AI hot-fix
node pipeline/bridge.js design "<idea>"             # end-to-end design loop (Operator engineer)
node pipeline/bridge.js operator "<task>"           # engineering loop: runtime edits (Operator)
node pipeline/bridge.js smoke ["<idea>"]            # one-command offline end-to-end proof
```

---

## 🧠 The orchestration stack

One brain commands a crew of free specialists:

| Role | Who | What it does |
|---|---|---|
| **Orchestrator** | **Buffy (Freebuff)** | Plans the game, dispatches designers and engineers, verifies, pushes, runs the release loop |
| **Operator** | OpenCode CLI (`operators/`) | The in-repo engineering brain: derives GameSpecs end-to-end (`design`), edits the runtime (`operator`), hot-fixes crash logs (`fix`) |
| **Design brain** | DeepSeek (via Freebuff) | Turns a prompt into a complete, balanced GameSpec JSON (`newgame`) |
| **Art director** | Meshy AI | Text-to-3D assets for maps, enemies and props (`asset`, `props --sync`) |
| **Asset host** | Roblox Open Cloud | Auto-uploads generated models and returns live `rbxassetid://` links |
| **Quality gate** | `validate_luau.js` + test runner | `--!strict`, naming, block balance, JS syntax, self-simulating Studio tests |

```
idea ──► design ──► compile ──► gate ──► test ──► fix ──► iterate
 │        │           │          │         │        │
 │   Operator     codegen    bridge.js   testrunner  autofix.js
 │   derives    emits typed    verify    __TESTING   parses crash
 │   the spec    config.luau   (Luau+JS)  in Studio   logs → patch
 └──── user's words become a game; failures feed back in
```

---

## 📁 What's inside

| Layer | What it is |
|---|---|
| **`pipeline/`** | CLI + master derivation prompt + DeepSeek designer + Meshy 3D client + Open Cloud auto-upload + crash hot-fix loop + Operator game-design engineer + game-type scaffolder + Luau validator + logo→icon builder |
| **`src/shared/config.luau`** | **The GameSpec** — game type, rounds, enemies, weapons, perks, economy, doors, map, lighting, style guide, anti-cheat, UI theme, audio identity |
| **`src/server/`** (Luau) | Generic authoritative engine: procedural map + nav graph + lighting + atmosphere, enemy AI & scaling, round state machine, hitscan + anti-cheat, economy + persistence, shop, audio director, devlog, compressed batched networking, self-simulating test runner |
| **`src/client/`** (Luau) | UI framework, data-driven HUD, FPS camera + spring-physics viewmodel, entity interpolation + local death VFX |
| **`plugin/`** | **RBLX Operator Craft** — Studio plugin: devlog console, one-click playtest, lighting mood presets, GameSpec preview, Meshy injector |
| **`site/`** | GitHub Pages landing site (pure HTML/CSS/JS) — opencode aesthetic |
| **`gametypes/`** | Game-type registry + packs — the unbounded-genre mechanism |
| **`assets/`** | Branding (logo → `icon.ico`, `logo-256.png`), generated models + registry, spatial prop manifest |
| **`docs/`** | WHITEPAPER · USER_MANUAL · ORCHESTRATION |
| **`examples/prompts/`** | Example derivation briefs |

---

## 📜 License & credits

MIT licensed. Built and orchestrated by **Buffy (Freebuff)** with **Operator
(OpenCode)** as the in-repo engineering brain, **DeepSeek** as the design
brain, and **Meshy AI** + **Roblox Open Cloud** for art direction. See
`AUTHORS.md`.

**Ship something great.**

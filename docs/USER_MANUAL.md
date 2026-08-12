# RBLX Operator — User Manual

Everything you need to go from *nothing installed* to *playing a game you
designed with a prompt* — and then to publish the system on GitHub.

**One sentence:** RBLX Operator is a free engine that derives a complete,
balanced, playable Roblox game from a prompt. It ships no games — you design
the game by describing it.

---

## 1. What you need

| Requirement | Needed for | Notes |
|---|---|---|
| **Node.js ≥ 18** | The pipeline (CLI, design, assets, fixes) | [nodejs.org](https://nodejs.org); `node --version` to check |
| **Desktop app** (optional) | Everything, no terminal | The whole system as an .exe; bundles Node — see §9b |
| **Rojo** (optional for play) | Building the `.rbxl` game file | [rojo.space](https://rojo.space); `scripts/studio.ps1` installs it via Rokit |
| **Roblox Studio** | Playing / testing the game | Free |
| **API keys** (optional) | AI design, 3D assets, auto-uploads | Everything works with zero keys |

---

## 2. Quickstart (60 seconds, zero keys)

```bash
# 1. Clone/download the repo and open a terminal inside it
git clone <your-repo-url> rblx-operator
cd rblx-operator

# 2. Scaffold .env (optional — skip if you want zero keys)
node pipeline/bridge.js init

# 3. (Optional) install Rojo once:  https://rojo.space   (or run scripts\setup.bat, choice 2)

# 4. Build the game file
rojo build default.project.json -o RobloxOperator.rbxl

# 5. Open RobloxOperator.rbxl in Roblox Studio and press Play
```

That plays the engine's **reference game** — a full round-based survival
shooter. Now derive your own:

```bash
node pipeline/bridge.js newgame "a grim zombie survival shooter where you hold
barricaded windows and buy weapons off the walls"
rojo build default.project.json -o RobloxOperator.rbxl
```

New game. Same engine. One prompt.

---

## 3. The workflow: prompt → game

There is exactly one way to get a game: **describe it**. Three routes:

### Route A — the pipeline designs it (needs a DeepSeek key)

```bash
# Add DEEPSEEK_API_KEY=... to .env (see §5), then:
node pipeline/bridge.js newgame "a tense extraction shooter: raid the harbor,
loot the vault, extract by wave 5 or die trying"
```

The pipeline sends your idea to DeepSeek with the master derivation prompt
(`pipeline/system_prompt.md`) as its system prompt, validates the JSON it
returns, clamps every number, and writes:

- `games/<name>/spec.json` — the design (human-readable, editable)
- `src/shared/config.luau` — the typed spec the engine compiles

### Route B — any AI chat designs it (no DeepSeek key)

The master prompt works with **any** model. Claude, ChatGPT, Gemini — whatever
you already have:

```bash
node pipeline/bridge.js prompt   # prints the master derivation prompt
```

1. Copy the printed text as the **system prompt** of your chat.
2. Send your game idea as the user message. (See `examples/prompts/*.md` for
   well-written briefs.)
3. Save the JSON it returns to a file, e.g. `mygame.json`.
4. Import it:

```bash
node pipeline/bridge.js newgame --spec mygame.json
```

This is the "commoditize the design" path: the design intelligence is not
locked to any one model or service.

### Route C — offline (zero keys, zero wait)

```bash
node pipeline/bridge.js newgame --offline "futuristic neon alien wave shooter"
```

The offline path reads theme/goal signals out of your prompt (neon? extraction?
tower defense? horror?) and re-themes the reference spec accordingly — the
engine visibly becomes your game, but the design is a nudge, not an invention.
Use it to prototype, and Route A or B for the real design.

### Route D — human (always available)

The spec is plain data. Edit `games/<name>/spec.json` (or `config.luau`
directly) and rebuild. Every number in the game is in that file: damage,
fire rates, health scaling, door costs, spawn coordinates, lighting, UI colors.

### After any route

```bash
node pipeline/bridge.js verify          # all Luau + JS checks
rojo build default.project.json -o RobloxOperator.rbxl
```

---

## 4. CLI reference

```
node pipeline/bridge.js init                      Scaffold .env + directories
node pipeline/bridge.js prompt                    Print the master derivation prompt
node pipeline/bridge.js newgame "<idea>"          Design a full game (DeepSeek)
node pipeline/bridge.js newgame --spec <file>     Import a design from any AI chat
node pipeline/bridge.js newgame --offline "<idea>" Zero-key text derivation
node pipeline/bridge.js asset "<prompt>" [--kind=enemy|prop|...]
                                                  Generate a 3D asset (Meshy)
node pipeline/bridge.js props [--sync]            List the spatial prop manifest;
                                                  --sync generates + uploads models
node pipeline/bridge.js verify                    Validate all Luau + JS
node pipeline/bridge.js build / serve             Rojo build / live-sync steps
node pipeline/bridge.js test                      Run the self-simulating test runner
node pipeline/bridge.js fix --log logs/runtime.log Crash log -> AI hot-fix
node pipeline/bridge.js design "<idea>"           End-to-end design loop (OpenCode engineer)
node pipeline/bridge.js operator "<task>"         Engineering loop: runtime edits (OpenCode)
node pipeline/bridge.js smoke ["<idea>"]          One-command offline end-to-end proof
```

---

## 5. Keys (all optional)

Copy `.env.example` to `.env` and fill what you have. `.env` is gitignored —
your keys never leave your machine.

| Key | Service | What it unlocks | Where |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | DeepSeek | Novel AI game design (Route A) | platform.deepseek.com |
| `MESHY_API_KEY` | Meshy | Text-to-3D assets | meshy.ai |
| `OPEN_CLOUD_API_KEY` | Roblox Open Cloud | Auto-upload assets → live `rbxassetid://` | create.roblox.com → Credentials (scope: `assets:write`) |
| OpenCode (no key) | OpenCode CLI | Agent operations (`operator`) | `npm i -g opencode-ai` + `opencode auth login` |

Force offline even with keys: `USE_DEEPSEEK=false` in `.env`, or pass
`--offline`.

---

## 6. Studio workflow

**One-time build:**

```bash
rojo build default.project.json -o RobloxOperator.rbxl
```

**Live editing (recommended while iterating):**

1. Install the Rojo plugin (roblox.com/library/7168068472/Rojo).
2. `rojo serve default.project.json`
3. In Studio: Plugins → Rojo → Connect. Edit Luau → instant sync.

**Playing the reference game:** open the `.rbxl`, press Play. Mouse-look to aim,
click to fire, `R` to reload, `F`/`E` to interact (proximity prompts: doors,
wall buys, mystery box, pack-a-punch, perk machines, repair stations). You
bleed out when downed — a teammate can revive you.

**Your design** flows through automatically: new weapons, enemies, lighting,
HUD colors — all from the spec.

---

## 7. Testing your game

The engine can test itself. Enable the test runner by setting the place
attribute `__TESTING = true` (or `_G.__TESTING = true` in a Studio script
before Play). It will:

1. Validate the spec's structural integrity (zone chain, balances).
2. Spawn a dummy player, start rounds, and assert enemies spawn.
3. Fire the server-authoritative hitscan at a real enemy and assert damage.
4. Drive shop purchases and assert points are spent and rewards granted.

Every step prints `[TEST] PASS|FAIL ...` to Output, and the report is written
to `logs/runtime_test.log` (Studio) or a `TestResults` folder in workspace.

```bash
node pipeline/bridge.js test     # instructions
node pipeline/bridge.js fix --log logs/runtime_test.log   # auto-fix failures
```

---

## 8. The engineer loop (OpenCode operator)

OpenCode (`npm i -g opencode-ai`) is an optional **second brain**: a terminal
coding agent that can work end-to-end on this repo with any model you
configure (`opencode auth login --provider deepseek`). It reads its role — the
full engine contract, the schema, the verify gate — from
`pipeline/operators/engineer_persona.md`, which is prepended to every task.

**Design loop — one command, prompt to game:**

```bash
node pipeline/bridge.js design "a neon extraction shooter set on a derelict space station"
```

The engineer derives the complete GameSpec JSON (using
`pipeline/system_prompt.md`), the pipeline compiles it into
`src/shared/config.luau`, and the Luau gate runs. It prints a report with the
spec path, the config path, the roster sizes, and any gate failures. This is
Route A/B with a human engineer — except the engineer is an agent.

**Engineering loop — runtime changes:**

```bash
node pipeline/bridge.js operator "add a melee weapon system, spec-driven, with test runner coverage"
```

The persona keeps the runtime generic: new systems must read `config.luau`,
new remotes must be registered in `src/shared/constants.luau`, every file must
be `--!strict`, and the task isn't done until `node pipeline/bridge.js verify`
passes. The report tells you what changed and what's next.

**The full loop with `fix`:**

1. `design "<idea>"` (or `newgame` / `--spec`) to get the game.
2. Playtest (or `__TESTING` test runner) → copy failures to
   `logs/runtime.log`.
3. `fix --log logs/runtime.log` hot-patches runtime errors.
4. `operator "<task>"` for bigger system work.
5. `smoke` after any pipeline edit to re-prove the whole loop.

No OpenCode? The four routes in §3 and the `fix` loop cover everything;
`design` is the convenience route when you have OpenCode configured.

## 8b. The play → crash → fix loop

1. Playtest (or run the test runner). Copy any stack trace from the Studio
   Output into `logs/runtime.log`.
2. `node pipeline/bridge.js fix --log logs/runtime.log` — the pipeline parses
   stack traces, maps instance paths back to repo files, asks DeepSeek for the
   corrected file, and writes it back (original kept as `.bak`).
3. Rebuild and re-test.

For bigger changes — new systems, refactors — delegate to the OpenCode agent:

```bash
node pipeline/bridge.js operator "split the shop module into three focused modules"
```

---

## 9. Publishing to GitHub

The repo is GitHub-ready: MIT license, CI that validates on every push, and a
one-click publisher. **Fastest path — double-click `scripts\setup.bat`, choose
option 1.** That script (PowerShell behind the scenes) will:

1. Install **Git for Windows** via winget if you don't have it.
2. Run the **verify gate** (`node pipeline/bridge.js verify`) — no push until
   every Luau + JS check passes.
3. **Commit** everything (a neutral identity is set if you have none; you can
   change it later with `git config user.name/email`).
4. **Link your GitHub account** (the only manual step) and **create the
   repo** — see below.
5. **Push** to `origin/main`. CI then validates the push automatically.

### Linking your GitHub account (the one-time step)

There is exactly one manual step: authorizing GitHub. The script handles it
for you when you run it:

- **Browser login (recommended):** the script installs the GitHub CLI (`gh`)
  if needed, then runs `gh auth login` — a browser opens with a **one-time
  code**, you log in (or create the account there) and paste the code back.
  Done — the script immediately creates the repo and pushes.
- **Or manually, once:** in any terminal run `winget install GitHub.cli`,
then `gh auth login`. Re-run `setup.bat` → 1.
- **Or without gh:** create an empty repo at github.com/new and paste its URL
  when the script asks. The first `git push` then opens a browser sign-in
  (Git Credential Manager) — completing that also links your account.

**"Nothing happened"?** The script never exits silently — it pauses on every
message and prints the verify gate's output. If a window closed with no text,
Node.js was probably missing (`setup.bat` now offers to install it). If it
stopped at a prompt, it was waiting for the GitHub link (step 4). Re-run it.

Manual equivalent (or if you prefer the terminal):

```bash
# 1. Safety check — your keys must not be committed:
cat .gitignore          # should include .env, logs/, *.log, assets/generated/, games/*/
ls -la                  # confirm no .env is present

# 2. Initialize and commit:
git init
git branch -M main
git add .
git commit -m "RBLX Operator: prompt-to-Roblox-game engine"

# 3. Create an empty repo on GitHub (github.com/new), then:
git remote add origin https://github.com/<you>/rblx-operator.git
git push -u origin main
```

**No secrets can leak:** `.env` is gitignored, and `push.ps1` aborts if it ever
finds `.env` tracked. Node is required (the verify gate); install it from
[nodejs.org](https://nodejs.org) if `setup.bat` complains.

GitHub Actions will run CI automatically: **Luau + JS validation** and an
**offline derivation smoke test** (a prompt → spec → re-verify). The badge:

```markdown
[![CI](https://github.com/<you>/rblx-operator/actions/workflows/ci.yml/badge.svg)](https://github.com/<you>/rblx-operator/actions/workflows/ci.yml)
```

**Downloaders then run:**
`node pipeline/bridge.js init` → `newgame "<idea>"` → `rojo build`.

---

## 9b. The desktop app (.exe)

The entire system is also packaged as a Windows desktop app — **Roblox
Operator Studio** — so users can make games with **no terminal and no
Node.js**: the app bundles the engine and its own Node runtime. The only
thing a user still installs is Roblox Studio (and Rojo for the build step —
the app prints the one-line install, or run `scripts/studio.ps1`).

**Getting the .exe (free, no build needed):**

1. Push the repo — every push runs the **Build EXE** workflow on GitHub
   Actions. Open **Actions** → *Build EXE* → newest run → **Artifacts** →
   download `rblx-operator-windows`.
2. For a permanent download: tag a release (`git tag v1.0.0` then
   `git push --tags`) — the installer + portable .exe are attached to the
   **Releases** page.
3. Or build locally: `npm run app:install` then `npm run app:build`
   (output: `app/dist/`). Run from source anytime with `npm run app:start`.

**What it does:**

| Tab | What it does |
|---|---|
| 🎨 **Design** | Type a game idea; mode = OpenCode engineer loop (`design`) / DeepSeek (`newgame`) / offline (zero keys) / import a spec from any AI chat (`--spec`) |
| 🧪 **Verify** | Full Luau + JS gate, end-to-end `smoke`, and one-click `rojo build` → opens in Roblox Studio |
| 🚀 **Publish** | Link your GitHub account (browser + one-time code), create the repo & push — same safe gate as §9 |
| 📁 **Projects** | Every design you've made (`games/<name>/spec.json`) — recompile any one |
| ⚙️ **Settings** | API keys → written to `.env` (gitignored) |

**Where your work lives:** the packaged app seeds a per-user workspace at
`%APPDATA%\RBLX Operator\workspace` — games, `.env` keys, logs and
the generated `.rbxl` all live there, and the installed files are never
touched. In source mode (`npm run app:start`) it operates on the repo itself.

---

## 10. FAQ / troubleshooting

**Quick end-to-end check after any change:**
`node pipeline/bridge.js smoke` — if it passes, the pipeline is healthy.

**"I double-clicked setup.bat and nothing happened."**
It never exits silently — every message ends with a pause, so a closed window
means it ended at a `pause` you closed past, or the window never opened. The
usual causes, in order: (1) Node.js isn't installed (`setup.bat` now offers
to install it; otherwise nodejs.org), (2) the verify gate printed red text,
(3) it was waiting for the GitHub account link (§9 — that's the one manual
step: browser + one-time code). Re-run and read the last lines.

**"How do I link my GitHub account for the push?"**
Run `scripts/setup.bat` → 1 (or `scripts/push.ps1`). It installs the GitHub
CLI if needed and runs `gh auth login` — a browser opens, you log in and
paste the one-time code back. Alternatively create an empty repo at
github.com/new and paste its URL when asked; the first push then opens a
browser sign-in (Git Credential Manager). Either way, the account link is a
browser login — see §9 "Linking your GitHub account".

**"I ran `newgame` with no key and it says 'offline derivation'."**
Correct. Zero-key mode nudges the reference spec from your prompt's theme/goal
signals. For a novel design, add a `DEEPSEEK_API_KEY`, use Route B (any AI
chat + `--spec`), or hand-edit the spec.

**`verify` reports a JS or Luau issue.**
Fix, then re-run `verify`. CI runs the same checks.

**Studio says a script errored at boot.**
The most common cause is a hand-edited spec that violates the schema (e.g. a
door referencing an unknown zone). `bridge.js fix --log logs/runtime.log` can
patch it; or regenerate the spec from a prompt.

**"Can it make a racing game?"**
The engine is an action-shooter runtime — it derives survival, extraction,
defense, arena and boss-hunt games out of the box. A genuinely different genre
needs new systems: brief the OpenCode engineer (`operator "<task>"`) to add
them, following the existing module conventions.

**"What does `smoke` do?"**
`node pipeline/bridge.js smoke` runs the whole loop with zero keys and zero
OpenCode: it derives a game offline from a prompt (default: the neon-arena
brief), compiles `src/shared/config.luau`, and runs the full Luau + JS verify
gate — one command that proves the pipeline end to end. CI runs it on every
push. Pass a prompt to smoke-test a different idea:
`smoke "a grim medieval defense game"`.

**"`design` says OpenCode isn't installed."**
That's expected — OpenCode is optional. `npm i -g opencode-ai`, then
`opencode auth login --provider deepseek` (or any provider). On Windows,
OpenCode needs Git Bash: set `OPENCODE_GIT_BASH_PATH` in `.env`. Or just use
Route A (`newgame`) / Route B (`--spec`) — the design is the same interface.

**Assets look blocky.**
Procedural models are the zero-key baseline. Generate bespoke meshes with
`asset "<prompt>"` and let Open Cloud upload them straight into Roblox.

**Keys in `.env` didn't take effect.**
`bridge.js` reads `.env` at startup; restart the command after editing. Verify
the key has no quotes or trailing spaces.

---

*Full architecture: see `docs/WHITEPAPER.md`. Derivation examples:
`examples/prompts/`. Engine code: `src/`.*

# RBLX Operator — Architecture Whitepaper

**A free, open-source, prompt-to-game engine that commoditizes triple-A-quality
Roblox game design.**

*Version 1.0 — companion to the code in this repository.*

---

## 1. Abstract

Roblox game development is bottlenecked by craft: a commercial-quality
round-based survival game (Michael's Zombies, Call of Duty Zombies caliber)
requires systems design, economy tuning, networking, anti-exploit work, UI
engineering and art direction. AI is excellent at *writing code* and terrible
at *shipping games* — generated scripts are one-offs, untyped, unbalanced, and
unplayable as a system.

RBLX Operator inverts this. It separates **the game design** from **the game
engine**:

- **The engine** is a fixed, hand-built, generic Luau runtime — typed,
  server-authoritative, networked, tested — that can play an enormous range of
  action games. It ships once, is validated, and never changes per game.
- **The design** is data: a `GameSpec` (a JSON/Luau table) that the runtime
  renders. The spec is the entire game — balance, rosters, economy, map,
  lighting, UI theme.
- **The derivation** is a prompt: a single master system prompt that turns any
  game idea into a complete, balanced `GameSpec`, via any capable AI model.

Because design is data and the engine is generic, **one prompt changes the
game** — not by rewriting code, but by rewriting data the engine already
understands. This is the difference between AI-generated junk and
AI-assisted game development.

## 2. Why AI can't ship games today

Typical AI-generated Roblox projects fail on five axes:

1. **Context-window death.** A full game is tens of thousands of lines; no
   model holds it coherently. Outputs drift, contradict, and break.
2. **No balance.** Numbers are invented, not designed. Economies don't pace,
   difficulty curves don't curve.
3. **No architecture.** Scripts are monolithic one-offs: no type safety, no
   network separation, no anti-cheat, no UI framework.
4. **No validation.** Nothing checks whether the result is playable.
5. **No feedback loop.** Nobody plays the thing, so nobody fixes the thing.

RBLX Operator answers each one structurally (below).

## 3. The core insight: the game is data

Every gameplay system — rounds, enemies, weapons, perks, economy, purchases,
map layout, lighting, UI colors — reads from one typed contract,
`src/shared/config.luau`, generated against `src/shared/types.luau`. The
runtime contains **no game-specific logic**. The `GameSpec` is:

- **Small enough to design in one shot** (~600 lines of data), so a model can
  hold and reason about the whole game at once — no context-window death.
- **Complete enough to be a real game** — it is the entire design surface.
- **Human-editable** — the spec is plain data; anyone can tune it by hand.
- **Statically checked** — `sanitizeSpec` clamps every numeric field, so a
  hallucinated comma or a negative damage value degrades to a default instead
  of a crash.

The engine is the fixed cost; the spec is the variable cost that AI (or a
human) pays per game. This is the "compiler" model: AI writes the program in a
safe DSL, not in raw machine code.

## 4. The derivation contract

`pipeline/system_prompt.md` is the **master derivation prompt**. It is a
complete design brief taught to the model: the quality bar (commercial
polish), the exact schema, the derivation method (goal → round structure,
theme → art direction + lighting + UI tokens, roster design, economy pacing,
map layout), and the rules. It is the design interface of the whole system,
and it is deliberately **model-agnostic**:

| Route | How |
|---|---|
| Pipeline (DeepSeek) | `bridge.js newgame "<idea>"` sends the prompt to `deepseek-chat` with `response_format: json_object` |
| Any AI chat | Paste the prompt as the system prompt, get JSON, import with `--spec` |
| Offline | Zero-key text derivation reads theme/goal signals and nudges the reference spec |
| Human | Edit `games/<slug>/spec.json` directly and regenerate |

The engine ships the Zombie Rush reference game. The committed `config.luau` is the engine's
reference spec — the minimal playable starting point every derived game is
built from and measured against. Nothing in the repo pretends to be *the*
game.

## 5. The pipeline (Node, zero dependencies)

`pipeline/` is a dependency-free Node orchestrator. `bridge.js` is the CLI
router:

- **`codegen.js`** — prompt → validated `GameSpec` → typed `config.luau`.
  Structured-output validation: JSON shape checks, per-field clamps, door-chain
  reconstruction, and merging of the spatial prop manifest. Emits Luau with
  `Color3`/`Vector3` literals matching the type schema.
- **`meshy_client.js`** — Meshy v2 text-to-3D client (generate → poll → download).
- **`opencloud.js`** — Roblox Open Cloud Assets uploader: GLBs go straight to
  Roblox (`apis.roblox.com/assets/v1/assets` → poll → `rbxassetid://`), writing
  live asset links into the registry and the spatial manifest. No manual Studio
  importing.
- **`registry.js`** — asset catalog manager.
- **`autofix.js`** — crash-log → DeepSeek hot-fix loop: parses stack traces,
  maps instance paths to repo files, patches, keeps `.bak`.
- **`operators/`** — the **OpenCode game design engineer**. `engineer_persona.md`
  is the agent's brain: the engine contract (game-is-data, generic runtime,
  schema, constants registration, verify gate) and the engineering loop.
  `opencode_operator.js` injects it into every task and orchestrates
  `designGame()` — the end-to-end design loop: idea → engineer derives a
  GameSpec JSON → `codegen` compiles `config.luau` → the Luau gate runs → a
  structured report (spec path, roster sizes, gate issues) comes back. Any
  model works (`opencode auth login --provider deepseek`).
- **`validate_luau.js`** — repo validator (`--!strict` header, Rojo naming,
  block balance). `bridge.js verify` runs it plus `node --check` on all JS;
  GitHub Actions runs both on every push. `bridge.js smoke` is the one-command
  end-to-end proof (offline derivation → compile → verify) that CI also runs.

## 6. The runtime architecture

```
src/
├── shared/    ReplicatedStorage — types, config (the spec), constants,
│              networking wrapper, pack (int-keyed compression), signal, math
├── server/    ServerScriptService — the authoritative engine
└── client/    StarterPlayerScripts — the presentation engine
```

**Server (authoritative):**

- `mapbuilder.luau` — procedurally builds the map from the spec (zones, walls,
  windows, barricades, doors, props), a waypoint nav graph with LOS shortcuts
  (no NavMesh), and a **dynamic lighting profile** — Atmosphere, sky, fog,
  exposure, clock time — all data-driven, plus style-guide materials.
- `rounds.luau` — state machine: lobby → intermission → spawning → combat →
  round end → game over, with **objective wins** (`winRound > 0` = extraction
  games) and boss-round pacing.
- `enemies.luau` — spawning, round scaling, AI (pathing, barricade targeting,
  attacks), damage, and the **compressed batch channel**: one
  `EnemyStateBatch` remote at `config.net.enemyBatchHz` carries integer-keyed
  state plus **death events**, instead of per-enemy chatter.
- `combat.luau` — server-authoritative hitscan (fire-rate, ammo, raycast,
  distance, LOS validation) with anti-cheat hooks.
- `anticheat.luau` — heartbeat movement sampling (teleport/speed detection with
  snap-back or kick), wall-clip probes, impossible-shot-origin rejection.
- `players.luau`, `economy.luau`, `shop.luau` — health/regen/downed/revive,
  points + loadouts + DataStore persistence, and the purchase economy (doors,
  wall buys, mystery box, pack-a-punch, perks, barricade repair).
- `testrunner.luau` — a self-simulating player that validates the spec, spawns
  rounds, fires the real hitscan engine, and drives the shop; machine-parseable
  `[TEST] PASS|FAIL` output feeds the hot-fix loop.

**Client (presentation):**

- `combatclient.luau` — FPS camera, input, tracers; drives the viewmodel.
- `viewmodel.luau` — **spring-physics weapon feel**: damped springs
  (semi-implicit Euler) for sway, kick (scaled by the weapon's `recoil` stat),
  ADS blend, reload dip, walk bob. Feel is data.
- `entities.luau` — consumes the compressed batch, smooths counts/health/
  positions, and turns death events into local **blood bursts + ragdoll
  physics assemblies** (client-created, never replicated to the server).
- `ui/` — `uikit.luau` (theme-token framework: gradients, CanvasGroups,
  rotating 3D ViewportFrame previews), `hud.luau`, `menus.luau`.

**Why it scales:** the server broadcasts ~10 ints per enemy at a fixed low rate;
clients interpolate. Kills ride the same channel as state. 150+ enemies is a
client rendering problem, not a server networking problem.

## 7. The feedback loop

A game that isn't played and fixed is a demo. Operator closes the loop — and
with the OpenCode engineer it becomes **three loops that share one brain**:

1. **Design loop** — `bridge.js design "<idea>"`: the OpenCode engineer derives
   the GameSpec (via the master derivation prompt), the pipeline compiles it,
   and the Luau gate runs, all in one command. Failures come back as a report
   naming the exact gate issue.
2. **Playtest → fix loop** — human in Studio (or the `testrunner`
   self-simulator) → copy the crash/output log to `logs/runtime.log` →
   `bridge.js fix --log` maps stack traces back to repo files and DeepSeek
   patches them.
3. **Engineering loop** — `bridge.js operator "<task>"` for bigger work on the
   runtime itself: new systems, refactors. The engineer persona keeps it
   generic (spec-driven, `--!strict`, constants registered) and won't call a
   task done until `bridge.js verify` passes.

Every loop stage is a command; `bridge.js smoke` re-proves the whole pipeline
(offline derivation → compile → verify) in one shot, and CI runs it on every
push. Rebuild with `rojo build` → next playtest.

## 8. Economics

The system is free by construction:

- **Zero keys required.** Maps, enemies, weapons, UI are all procedural; the
  offline derivation path runs with no API access. `verify`, `build`, and the
  CI pipeline run with zero keys.
- **Drop-in upgrades, all optional:** DeepSeek (design), Meshy (3D assets),
  Roblox Open Cloud (asset uploads), OpenCode (agent operations). Every failure
  path degrades gracefully to the previous tier.
- **No dependencies.** The pipeline is pure Node stdlib; the runtime is pure
  Luau + Rojo.

## 9. Threat model and honest limitations

- **Scope is the action genre.** The engine is an FPS/action runtime
  (hitscan, rounds, waypoint enemies, purchase economy). It derives enormous
  variety *within* that scope — survival, extraction, defense, arena, boss
  hunts — but a racing game or a full RPG needs new systems; the master prompt
  says so, and the OpenCode operator exists to extend the runtime.
- **Procedural art is stylized, not photoreal.** Assets are low-poly
  procedural models with style-guide materials; Meshy + Open Cloud uploads are
  the upgrade path to bespoke meshes.
- **Anti-cheat is pragmatic, not absolute.** Speed/teleport/wall-clip/LOS
  enforcement stops the common exploit classes; it is tunable and does not
  claim to be bulletproof against sophisticated clients.
- **The offline path is derivation, not invention.** Without a model, the
  prompt is reduced to theme/goal hints over the reference spec — enough to
  prove the architecture, not to design a novel game. That is what the
  (cheap, optional) model route is for.

## 10. Conclusion

RBLX Operator's bet is simple: **game design is a data problem, not a code
problem, and the data can be designed by a prompt.** By fixing the engine and
deriving the design, it turns an AI's weakness (holding a whole game in
context) into a strength (holding a whole design in context), and turns a
developer's weakest asset — time — into the only thing they must spend: the
words that describe the game they want.

MIT licensed. Build something great.

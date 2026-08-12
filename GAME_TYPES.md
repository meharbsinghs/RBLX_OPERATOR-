# Game types — the unbounded-genre mechanism

**The ceiling is not bounded.** The engine ships the action-shooter family
today; `bridge.js newtype` makes *every other genre* a first-class pack that the
Operator can build. This file is the contract for how.

---

## What ships today (live modes)

The shipped runtime (`src/server/rounds.luau` + the combat/economy/shop/enemies
family) is one generic engine with five *modes*, chosen by the spec's
`gameType` and tuned by round knobs:

| gameType | Goal | Key knobs |
|---|---|---|
| `wave` | Endless survival | `winRound: 0` |
| `extraction` | Survive + extract by wave N | `winRound: 3–8`, `bossEvery: 1–3`, rich `points.starting` |
| `defense` | Hold the wall under siege | high `baseEnemies`/`maxEnemies`, `barricadeHp` up |
| `arena` | Gauntlets & boss hunts | `winRound: N`, compact zones |
| `boss-rush` | A boss every round | `bossEvery: 1`, elite rosters |

Everything else — obbies, tycoons, racing, RPGs, sandbox, sports, sims — is a
**game-type pack**: a directory of typed Luau runtime modules + a spec schema
fragment that the Operator authors once, and that every derived game of that
genre then renders.

## The mechanism

### 1. Scaffold the pack

```bash
node pipeline/bridge.js newtype "Obby" "obstacle course platformer: jump, climb, avoid hazards, reach the end"
```

This creates `gametypes/obby/`:

```
gametypes/obby/
├── README.md              # the design contract for this genre
├── spec.fragment.json     # the spec schema this genre adds
└── runtime/               # Operator-authored typed Luau modules go here
```

…and registers the type in `gametypes/registry.json` so the design prompt and
the plugin know it exists.

### 2. Operator authors the runtime

The **Operator** (OpenCode, `pipeline/operators/engineer_persona.md`) fills
`runtime/` with `--!strict` Luau following the engine contract:

- every new remote/tag/folder/attribute is registered in
  `src/shared/constants.luau`
- the pack reads its schema from the GameSpec (`src/shared/config.luau`),
  never hardcodes a game
- the pack bootstraps from `src/server/init.server.luau` (or dispatches from
  `config.gameType`)
- it ends every session with `node pipeline/bridge.js verify`

```bash
node pipeline/bridge.js operator "implement the obby runtime pack: spawn the
player at the start, hazard parts kill + respawn at checkpoint, finish pad
fires the win remote. Register remotes in constants.luau, read the spec schema
from games/<slug>/spec.json. --!strict, verify before done."
```

### 3. The design brain learns the type

Once registered, the master derivation prompt knows `obby` exists: a designer
(AI or human) can now produce an obby GameSpec and `newgame --spec` compiles it.
A new genre is one scaffold + one Operator session — then it's a first-class
type forever.

### 4. Craft + playtest surface

The **Studio Craft plugin** (`plugin/`) is the delivery side: devlog console,
one-click playtest, lighting/atmosphere presets, and asset injection (Meshy /
Open Cloud) for whatever the new genre needs — cars, NPCs, shop fronts, hazard
props.

---

## Why this is the honest architecture

A single runtime that "plays everything" would play nothing well. Instead:

- **Structure is guaranteed.** Every pack is `--!strict`, gated by `verify`,
  registered centrally, data-driven. No per-game one-off scripts.
- **Craft is unbounded by design.** Genre-specific feel — vehicle physics,
  obby jump arcs, tycoon automation, quest pacing — is authored once per type
  by the Operator, not re-derived per game.
- **Quality per game still comes from the design.** The engine supplies
  systems, structure and the playtest loop; the derived spec supplies balance,
  theme, sound identity and story. The two together are what "Michael's
  Zombies caliber" is made of — and the loop above makes both repeatable.

## Status

| Type | Status |
|---|---|
| wave, extraction, defense, arena, boss-rush | **live** — playable now |
| obby, tycoon, racing, rpg | **scaffold** — registered, runtime pending Operator session |
| anything else | one `newtype` away |

MIT licensed.

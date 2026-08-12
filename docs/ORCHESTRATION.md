# RBLX Operator — Orchestration

RBLX Operator is built to be **commanded**, not clicked. One orchestrator
(**Buffy · Freebuff**) plans the game, dispatches specialists, verifies
everything, and runs the release loop. This is the command manual.

## The crew

| Role | Who | How to command |
|---|---|---|
| Orchestrator | **Buffy (Freebuff)** | Just describe the goal. Buffy plans, dispatches, verifies, pushes, and iterates. |
| Engineer | **Operator (OpenCode)** | `node pipeline/bridge.js operator "<task>"` |
| Designer (end-to-end) | Operator via `design` | `node pipeline/bridge.js design "<idea>"` |
| Designer (prompt only) | DeepSeek / any AI | `node pipeline/bridge.js newgame "<idea>"` or paste `bridge.js prompt` into any chat → `--spec` |
| Designer (offline) | text derivation | `node pipeline/bridge.js newgame --offline "<idea>"` |
| Art director | Meshy AI | `node pipeline/bridge.js asset "<prompt>" --kind=enemy` · `props --sync` |
| Asset host | Roblox Open Cloud | automatic (set `OPEN_CLOUD_API_KEY`) |
| Quality gate | `bridge.js verify` + test runner | `node pipeline/bridge.js verify` · `_G.__TESTING = true` in Studio |
| Fixer | `autofix.js` | `node pipeline/bridge.js fix --log logs/runtime_test.log` |

## The loop

```
1. PLAN      Orchestrator turns the goal into a spec brief (prompt).
2. DESIGN    Operator/DeepSeek derives the GameSpec JSON.
3. COMPILE   codegen emits src/shared/config.luau (typed, clamped, safe).
4. GATE      bridge.js verify — Luau --!strict + naming + balance, JS syntax.
5. BUILD     rojo build default.project.json -o RBLXOperator.rbxl
6. PLAYTEST  Studio + Craft plugin (devlog console, lighting, asset inject).
7. FIX       crash log / test output → autofix.js → Operator patches → 2-6.
8. SHIP      push → CI (verify + smoke + Build EXE) → Pages site updates.
```

## New genre in one session

1. `node pipeline/bridge.js newtype "Racing" "vehicles, checkpoints, timers"` —
   scaffolds `gametypes/racing/` and registers it.
2. `node pipeline/bridge.js operator "implement the racing runtime pack…"` —
   Operator authors the typed Luau + schema (see `GAME_TYPES.md`).
3. Design races with `newgame --spec` (any AI chat, master prompt) — the type
   is now a first-class citizen.

## Rules of the road (the engine contract)

- The game is data (`src/shared/config.luau`); the runtime stays generic.
- Every `.luau` is `--!strict`; remotes/tags/folders go in `constants.luau`.
- Never commit `.env`. Always end a session with `bridge.js verify`.
- New systems go through the gate before they're trusted.

MIT licensed.

# RBLX Operator — Authors & Crew

**RBLX Operator** is a prompt-to-Roblox-game engine built as an **orchestrated
system**: one orchestrator commands a crew of free specialists. This file
credits that crew.

| Role | Name | Contribution |
|---|---|---|
| **Orchestrator & system builder** | **Buffy (Freebuff)** | Designed and built the whole system end-to-end: the pipeline, the rebrand, the site, the plugin, the game-type architecture, the release loop. Commands every stage: plan → design → build → verify → push → playtest. |
| **Repo owner / product owner** | **meharbsinghs** | The human behind the system — the end goal, the direction, and every creative call (the BUILDERBOI mascot, the "Michael's Zombies caliber" quality bar). |
| **Engineering sub-operator** | **Operator (OpenCode)** | The in-repo engineering brain: end-to-end game design (`bridge.js design`), runtime engineering (`bridge.js operator`), crash-log hot-fixes (`bridge.js fix`). |
| **Design brain** | **DeepSeek** | Turns a game idea into a complete, balanced GameSpec JSON via the master derivation prompt. |
| **Art director** | **Meshy AI** | Text-to-3D assets for enemies, props and maps — the craft that goes beyond simple bricks. |
| **Asset host** | **Roblox Open Cloud** | Auto-uploads generated models and returns live `rbxassetid://` links. |
| **Quality gate** | `validate_luau.js` + the self-simulating test runner | `--!strict`, naming, block balance, JS syntax, and in-Studio tests on every push. |

## The deal

The system **ships games** — complete, balanced, playable Roblox games from
a single prompt. The crew above is what turns
*a prompt* into *a playable, balanced, crafted Roblox game*:

```
you ──► Buffy (orchestrator) ──► Operator/DeepSeek (design)
                                   │
                                   ├─► Meshy + Open Cloud (art)
                                   │
                                   └─► codegen → config.luau → verify gate
                                         │
                                         └─► Studio Craft plugin (playtest)
                                               │
                                               └─► fix loop (failures feed back)
```

Everything here is free and open source. MIT licensed.

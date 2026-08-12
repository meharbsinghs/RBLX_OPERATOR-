# RBLX Operator Craft — Studio plugin

The **playtest + craft surface** of the RBLX Operator engine, inside Roblox
Studio. One dock, four tabs:

| Tab | What it does |
|---|---|
| **CONSOLE** | Live DevLog streamed by the running engine — rounds, boss spawns, purchases, test lines. Playtest sessions become fully observable. |
| **PLAYTEST** | One-click local test run (`TestService:Run()`). Set `_G.__TESTING = true` before Play to run the engine's self-simulating test suite. |
| **CRAFT** | Lighting mood presets (Dusk / Night / Neon / Day) + **Apply GameSpec mood** (paints the derived game's `map.theme.lighting` into Studio) + **asset injector** (drop a Meshy / Open Cloud `rbxassetid://` model at your mouse). |
| **SPEC** | The derived game's identity at a glance — name, game type, win condition, rosters, audio state. |

## Install (one command)

```bat
scripts\plugin.ps1
```

Installs Rojo via Rokit if missing, builds the plugin, and copies it to
`%LOCALAPPDATA%\Roblox\Plugins\RBLXOperatorCraft.rbxmx`. Restart Studio, then
use the **RBLX Operator** toolbar button (or Plugins menu).

## Manual build

```bash
rojo build plugin/plugin.project.json -o "%LOCALAPPDATA%\Roblox\Plugins\RBLXOperatorCraft.rbxmx"
```

Requires Rojo (`https://rojo.space` — or `scripts\studio.ps1` installs it via
Rokit). The project marks the script with `RunContext: Plugin`, which makes
Studio load it as a plugin.

## How it connects

The plugin reads the engine's `ReplicatedStorage.Remotes.DevLog`
remote (created by `src/shared/networking.luau`, named in `src/shared/constants.luau`) and subscribes to it, so it
works with any place built from this repo — the reference game or any game you
derive. Before the place is built it simply says *waiting for engine*.

## Notes

- The plugin is plain Luau with zero external dependencies — no plugin
  framework, no toolchain beyond Rojo.
- If the dock doesn't appear, open **Plugins → RBLX Operator Craft**.
- Asset injector: paste any `rbxassetid://…` (from the Creator Hub, Meshy
  uploads via `bridge.js asset`, or Open Cloud) and click **INSERT ASSET**.

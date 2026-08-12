# Obby — game type pack

obstacle course platformer: jump, climb, avoid hazards, reach the finish

## Design contract
- The runtime pack lives in `runtime/` — typed Luau modules, read ONLY
  from the GameSpec (src/shared/config.luau), never hardcoded games.
- Register every remote/tag/folder/attribute in src/shared/constants.luau.
- Bootstrap from src/server/init.server.luau (or dispatch on config.gameType).
- Every file starts with --!strict; finish with: node pipeline/bridge.js verify

## How to build it (Operator session)
  node pipeline/bridge.js operator "implement the obby runtime pack: read the spec schema from spec.fragment.json, wire remotes in constants.luau, bootstrap from init.server.luau. --!strict, verify before done."

Then design games of this type with newgame --spec (any AI chat) and
playtest through the Studio Craft plugin.

See GAME_TYPES.md for the full mechanism.

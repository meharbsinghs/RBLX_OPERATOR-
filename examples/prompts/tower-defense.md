# Example prompt — tower defense

> Copy this into `node pipeline/bridge.js newgame "<prompt>"`, or paste it as the
> user message in any AI chat whose system prompt is `pipeline/system_prompt.md`
> and import the JSON with `--spec`.

```
A build-and-hold defense game in the spirit of tower defense, first-person. The
wall is all that stands between the horde and the core. Players buy weapons,
open gates to expand the map, and repair barricades between bigger and bigger
waves.

Mood: cold mountain stronghold at night — stone, timber barricades, cool blue
torchlight, drifting fog. Style: grunge with a steel-blue palette. UI: blue
accent tokens on dark slate panels.

Mechanics spin: waves are larger and slower than a zombie game (more enemies,
higher cap, longer intermissions) so the fight is about the wall, not the
retreat. Barricade health is high; repair stations matter as much as guns.
Enemies: grunts, shielded runners, siege engines that hammer barricades, and a
colossus boss every 5 rounds.

Economy: rounds pay big (perRound high) and players start with some points to
arm up before wave 1 — the first minutes are prep, not panic. Doors open new
tiers of the stronghold with better wall buys and the pack-a-punch.

Balance so players who manage the wall and the economy survive indefinitely,
and sloppy play gets overrun by round 8.
```

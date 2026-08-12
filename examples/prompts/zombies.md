# Example prompt — zombie survival

> Copy this into `node pipeline/bridge.js newgame "<prompt>"`, or paste it as the
> user message in any AI chat whose system prompt is `pipeline/system_prompt.md`
> and import the JSON with `--spec`.

```
A grim, arcade-style zombie survival shooter in the spirit of classic round-based
zombies. Endless waves, no win condition — the goal is purely how long you hold
the line and how deep you push through the map.

Mood: decaying 1970s research facility at dusk — concrete, rust, warm sodium
lights, green fog. Style: gritty grunge. UI: blood-red accents on near-black
panels, amber highlights.

Weapons: a free knife and a starting pistol; wall buys for an SMG, a pump
shotgun and a bolt sniper; a rare wonder weapon that only comes from the mystery
box. Reload times and recoil should feel weighty and readable.

Enemies: shambling walkers in ever-growing hordes, fast runners that flank,
armored brutes that punish camping, and a towering boss every 5 rounds that
turns the whole arena into a fight.

Economy: knife/pistol kills fund the first door, then the pace should push
players through 4 zones with escalating door costs. Perk machines (health,
reload speed, fire rate, movement) and a pack-a-punch station for weapon
upgrades. Barricades hold windows; enemies smash them.

Balance so a decent player earns ~2000 points in the first 3 rounds but is
under real pressure by round 10.
```

# Examples — derivation prompts, not shipped games

The engine ships **no games**. These files are **example prompts** — the raw
inputs you feed the derivation pipeline to prove how much variety a single
engine can produce. Each one is a deliberately detailed game brief, written the
way you'd brief a human lead designer.

## The two ways to run one

**With the pipeline (DeepSeek key):**

```bash
node pipeline/bridge.js newgame "futuristic neon alien wave shooter — the grid
is infected, purge it in neon. Cyberpunk night: black glass, purple ambient,
cyan accents..."
```

**With any AI chat (no DeepSeek key):**

1. `node pipeline/bridge.js prompt` — prints the master derivation prompt
   (`pipeline/system_prompt.md`).
2. Paste it as the *system prompt* in any AI chat (Claude, ChatGPT, Gemini…),
   then send one of these files as the *user message*.
3. Save the JSON it returns and import it:

```bash
node pipeline/bridge.js newgame --spec mygame.json
```

**Or with zero keys locally:**

```bash
node pipeline/bridge.js newgame --offline "$(cat examples/prompts/neon-arena.md)"
```

The offline path reads theme/goal signals from the text and nudges the
reference spec — enough to see the engine re-theme itself, not a full novel
design. That is what the DeepSeek key (or the any-AI route) is for.

## The example briefs

| File | Game brief | What it exercises |
|---|---|---|
| `zombies.md` | Classic round-based zombie survival, endless waves | The benchmark genre: economy pacing, barricades, wonder weapon, boss rounds |
| `extraction.md` | Objective raid: extract on wave 5 or die trying | `winRound`, starting cash, boss pressure — a *goal*, not just survival |
| `tower-defense.md` | Build-and-hold: the wall is the game | Wave size/pace knobs, repair stations, prep phase economy |
| `neon-arena.md` | Futuristic neon alien wave shooter | Full theme flip: material style, lighting, enemy roster, UI tokens |

## Smoke test

The fastest way to prove the whole loop end to end — zero keys, zero OpenCode,
one command (CI runs exactly this on every push):

```bash
node pipeline/bridge.js smoke
```

That derives the neon-arena brief offline → compiles `src/shared/config.luau`
→ runs the full Luau + JS verify gate → prints PASS/FAIL. Pass a different
brief to smoke-test a different idea:

```bash
node pipeline/bridge.js smoke "a grim medieval defense game"
# or, from a brief file (Bash/macOS/Linux):
node pipeline/bridge.js smoke "$(cat examples/prompts/extraction.md)"
```

Then build what you derived:

```bash
rojo build default.project.json -o RobloxOperator.rbxl
```

Expected: `src/shared/config.luau` re-emits with a neon direction —
`styleGuide.material = "neon"`, cyan eye glow, purple night lighting profile
(clockTime ~0.4, elevated exposure), and a cyan HUD token set — and **verify**
passes. No UI code was touched; the tokens flipped the interface.

To run the same idea through the real design loop instead (OpenCode engineer,
if installed): `node pipeline/bridge.js design "$(cat examples/prompts/neon-arena.md)"`.

> `examples/neon-alien-arena/preset.json` (the old shipped preset) is
> deprecated and superseded by `examples/prompts/neon-arena.md`.

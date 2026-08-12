"use strict";

/**
 * Prompt -> GameSpec -> src/shared/config.luau
 *
 * The GameSpec is a complete, typed, data-driven game design: rounds, enemies,
 * weapons, perks, economy, purchases, map layout, lighting profile and UI
 * theme. The Luau runtime is fully generic — it renders whatever this spec
 * describes. This is the part that replaces "AI writes one-off scripts" with
 * "AI writes a real game design".
 *
 * The engine ships NO games. There is exactly one derivation interface:
 *
 *   1. DeepSeek (recommended) — the master system prompt in
 *      pipeline/system_prompt.md is sent to the designer model along with the
 *      user's idea; it returns a JSON spec that is structurally validated and
 *      sanitized against the runtime schema. The same prompt file works in ANY
 *      AI chat — the JSON it produces can be imported with --spec.
 *   2. Offline text derivation — a lightweight, zero-key fallback that reads
 *      theme/goal signals out of the prompt (neon? extraction? tower?) and
 *      applies small aspect deltas to the engine's reference spec. It is
 *      derivation, not a menu of shipped games. A DeepSeek key (or --spec)
 *      is the real path to novel, tuned design.
 */

const fs = require("fs");
const path = require("path");

const CONFIG_PATH = path.join(__dirname, "..", "src", "shared", "config.luau");
const GAMES_DIR = path.join(__dirname, "..", "games");
const SYSTEM_PROMPT_PATH = path.join(__dirname, "system_prompt.md");
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

// The master derivation prompt lives in its own committed file — it is the
// product's design interface. (Inline fallback so the module never hard-crashes
// if the file is missing from a partial checkout.)
let DESIGNER_PROMPT = null;
function getSystemPrompt() {
  if (DESIGNER_PROMPT === null) {
    try {
      DESIGNER_PROMPT = fs.readFileSync(SYSTEM_PROMPT_PATH, "utf8");
    } catch {
      DESIGNER_PROMPT = [
        "You are the lead game designer of an autonomous Roblox action-game engine.",
        "Given a game idea, return ONLY a JSON object: a complete, balanced GameSpec.",
        'Top-level keys: name, tagline, rounds { baseEnemies, enemiesPerRound, maxEnemies,',
        'intermissionSeconds, playerScaleCap, bossEvery, barricadeHp, winRound }, player',
        "{ maxHealth, regenDelay, regenRate, bleedoutSeconds, reviveSeconds, reviveRange },",
        "points { perHit, perKill, perHeadshotBonus, perRound, starting }, mysteryBoxCost,",
        "packCost, weapons[], enemies[], perks[], map { name, theme { floor, wall, accent,",
        "fog, lighting { ambient, outdoor, shiftTop, shiftBottom, brightness, clockTime,",
        "exposure, fogStart, fogEnd, atmosphereDensity, atmosphereOffset, atmosphereGlare,",
        "atmosphereHaze, skyColor } }, spawn, zones[], doors[], wallBuys[], boxes[],",
        "perks[], pack }. zones are rectangle rooms; the first has door null; later zones",
        "chain via doors. Colors are [r,g,b] 0-255. Return ONLY valid JSON.",
      ].join("\n");
    }
  }
  return DESIGNER_PROMPT;
}

const DEFAULTS = {
  name: "Zombie Rush",
  tagline: "Hold the line. Survive the horde.",
  // Game type: the genre contract this spec is designed for. "wave" is the
  // reference action mode; extraction/defense/arena/boss-rush are the other
  // modes of the shipped action runtime. Anything else is a scaffolded type
  // pack (gametypes/) — the unbounded-genre mechanism (see GAME_TYPES.md).
  gameType: "wave",
  rounds: {
    baseEnemies: 5,
    enemiesPerRound: 2,
    maxEnemies: 26,
    intermissionSeconds: 10,
    playerScaleCap: 3,
    bossEvery: 5,
    barricadeHp: 300,
    winRound: 0,
  },
  player: {
    maxHealth: 100,
    regenDelay: 6,
    regenRate: 12,
    bleedoutSeconds: 45,
    reviveSeconds: 3,
    reviveRange: 10,
  },
  points: { perHit: 10, perKill: 60, perHeadshotBonus: 30, perRound: 500, starting: 0 },
  mysteryBoxCost: 950,
  packCost: 5000,
  anticheat: {
    enabled: true,
    maxSpeed: 55,
    teleportThreshold: 30,
    strikesBeforeAction: 3,
    action: "teleport",
  },
  styleGuide: {
    material: "grunge",
    eyeColor: [255, 40, 30],
  },
  net: {
    enemyBatchHz: 5,
  },
  theme: {
    accent: [255, 180, 40],
    danger: [255, 60, 50],
    success: [90, 220, 120],
    bg: [12, 14, 18],
    panel: [18, 20, 26],
    panelLight: [30, 34, 42],
    text: [235, 238, 245],
    textDim: [150, 156, 168],
    overlay: [8, 8, 10],
  },
  weapons: [
    { id: "knife", name: "Combat Knife", kind: "melee", damage: 50, headshotMultiplier: 1, roundsPerSecond: 1.2, magSize: 0, reserve: 0, reloadTime: 0, spread: 0, recoil: 0.5, range: 8, pellets: 1, auto: false, wallBuyCost: 0, ammoCost: 0, color: [200, 200, 210], packTiers: [] },
    { id: "m1911", name: "M1911", kind: "gun", damage: 28, headshotMultiplier: 1.5, roundsPerSecond: 2.9, magSize: 12, reserve: 96, reloadTime: 1.3, spread: 0.015, recoil: 0.8, range: 250, pellets: 1, auto: false, wallBuyCost: 0, ammoCost: 250, color: [90, 92, 100], packTiers: [{ damageMultiplier: 1.6, magMultiplier: 1.4, nameSuffix: " Pack-a-Punched" }, { damageMultiplier: 2.2, magMultiplier: 1.8, nameSuffix: " Mark II" }] },
    { id: "mp5", name: "MP5", kind: "gun", damage: 24, headshotMultiplier: 1.5, roundsPerSecond: 10, magSize: 30, reserve: 180, reloadTime: 1.8, spread: 0.02, recoil: 1.1, range: 220, pellets: 1, auto: true, wallBuyCost: 1000, ammoCost: 400, color: [60, 64, 72], packTiers: [{ damageMultiplier: 1.6, magMultiplier: 1.4, nameSuffix: " Pack-a-Punched" }, { damageMultiplier: 2.2, magMultiplier: 1.8, nameSuffix: " Mark II" }] },
    { id: "ak47", name: "AK-47", kind: "gun", damage: 45, headshotMultiplier: 1.5, roundsPerSecond: 7.5, magSize: 30, reserve: 150, reloadTime: 2.1, spread: 0.028, recoil: 1.6, range: 320, pellets: 1, auto: true, wallBuyCost: 1500, ammoCost: 500, color: [110, 72, 46], packTiers: [{ damageMultiplier: 1.6, magMultiplier: 1.4, nameSuffix: " Pack-a-Punched" }, { damageMultiplier: 2.2, magMultiplier: 1.8, nameSuffix: " Mark II" }] },
    { id: "shotgun", name: "Pump Shotgun", kind: "gun", damage: 14, headshotMultiplier: 1.4, roundsPerSecond: 1.1, magSize: 8, reserve: 48, reloadTime: 2.6, spread: 0.06, recoil: 2.6, range: 90, pellets: 8, auto: false, wallBuyCost: 1200, ammoCost: 400, color: [120, 82, 44], packTiers: [{ damageMultiplier: 1.6, magMultiplier: 1.4, nameSuffix: " Pack-a-Punched" }, { damageMultiplier: 2.2, magMultiplier: 1.8, nameSuffix: " Mark II" }] },
    { id: "sniper", name: "L96 Sniper", kind: "gun", damage: 210, headshotMultiplier: 2, roundsPerSecond: 0.8, magSize: 5, reserve: 25, reloadTime: 2.8, spread: 0, recoil: 3, range: 600, pellets: 1, auto: false, wallBuyCost: 2000, ammoCost: 400, color: [70, 74, 82], packTiers: [{ damageMultiplier: 1.6, magMultiplier: 1.4, nameSuffix: " Pack-a-Punched" }, { damageMultiplier: 2.2, magMultiplier: 1.8, nameSuffix: " Mark II" }] },
    { id: "raygun", name: "Ray Gun", kind: "gun", damage: 130, headshotMultiplier: 1.25, roundsPerSecond: 5, magSize: 20, reserve: 120, reloadTime: 2.2, spread: 0.01, recoil: 1.2, range: 300, pellets: 1, auto: true, wallBuyCost: 0, ammoCost: 500, color: [120, 220, 255], packTiers: [{ damageMultiplier: 1.5, magMultiplier: 1.4, nameSuffix: " Mark II" }, { damageMultiplier: 2.0, magMultiplier: 1.8, nameSuffix: " Mark III" }] },
  ],
  enemies: [
    { id: "walker", name: "Walker", baseHealth: 100, healthPerRound: 14, speed: 12, damage: 12, attackRate: 0.9, points: 60, hitPoints: 10, color: [110, 150, 110], scale: 1, unlockRound: 1, spawnWeight: 10, isBoss: false },
    { id: "runner", name: "Runner", baseHealth: 60, healthPerRound: 10, speed: 24, damage: 8, attackRate: 0.7, points: 60, hitPoints: 10, color: [150, 190, 90], scale: 0.9, unlockRound: 3, spawnWeight: 6, isBoss: false },
    { id: "brute", name: "Brute", baseHealth: 450, healthPerRound: 45, speed: 8, damage: 28, attackRate: 1.3, points: 120, hitPoints: 10, color: [90, 70, 70], scale: 1.5, unlockRound: 5, spawnWeight: 3, isBoss: false },
    { id: "boss", name: "The Harbinger", baseHealth: 5000, healthPerRound: 800, speed: 13, damage: 60, attackRate: 1, points: 1000, hitPoints: 10, color: [60, 40, 40], scale: 2.4, unlockRound: 5, spawnWeight: 0, isBoss: true },
  ],
  perks: [
    { id: "jugg", name: "Juggernog", cost: 2500, description: "+100 max health", color: [255, 80, 60] },
    { id: "speed", name: "Speed Cola", cost: 3000, description: "30% faster reload", color: [80, 160, 255] },
    { id: "doubletap", name: "Double Tap", cost: 2000, description: "33% more fire rate", color: [255, 220, 60] },
    { id: "revive", name: "Quick Revive", cost: 1500, description: "Faster regen & bleedout", color: [60, 255, 120] },
    { id: "stamina", name: "Stamin-Up", cost: 2000, description: "20% faster movement", color: [255, 140, 60] },
  ],
  map: {
    name: "Greenwood Siege",
    theme: {
      floor: [35, 38, 30],
      wall: [55, 52, 44],
      accent: [255, 180, 40],
      fog: [25, 35, 28],
      lighting: {
        ambient: [30, 34, 42],
        outdoor: [42, 46, 56],
        shiftTop: [80, 74, 90],
        shiftBottom: [12, 14, 18],
        brightness: 1.15,
        clockTime: 19.5,
        exposure: 0,
        fogStart: 40,
        fogEnd: 220,
        atmosphereDensity: 0.3,
        atmosphereOffset: 0.1,
        atmosphereGlare: 0.25,
        atmosphereHaze: 1.2,
        skyColor: [30, 30, 40],
      },
    },
    spawn: [0, 4, 0],
    zones: [
      { id: "a", center: [0, 0, 0], size: [44, 30], door: null, windows: ["west", "south"] },
      { id: "b", center: [44, 0, 0], size: [44, 30], door: "d1", windows: ["east", "south"] },
      { id: "c", center: [40, 30, 0], size: [36, 30], door: "d2", windows: ["north"] },
      { id: "d", center: [4, 30, 0], size: [36, 30], door: "d3", windows: ["north", "west"] },
    ],
    doors: [
      { id: "d1", name: "East Gate", cost: 750, from: "a", to: "b" },
      { id: "d2", name: "North Passage", cost: 1000, from: "b", to: "c" },
      { id: "d3", name: "Inner Sanctum", cost: 1500, from: "c", to: "d" },
    ],
    wallBuys: [
      { id: "wb1", weaponId: "mp5", position: [-22, 2, 0] },
      { id: "wb2", weaponId: "shotgun", position: [66, 2, 0] },
      { id: "wb3", weaponId: "ak47", position: [40, 2, 45] },
      { id: "wb4", weaponId: "sniper", position: [-14, 2, 30] },
    ],
    boxes: [
      { id: "box1", position: [44, 0, 0] },
      { id: "box2", position: [4, 0, 24] },
    ],
    perks: [
      { id: "p1", perkId: "stamina", position: [0, 0, 6] },
      { id: "p2", perkId: "jugg", position: [30, 0, 24] },
      { id: "p3", perkId: "doubletap", position: [50, 0, 24] },
      { id: "p4", perkId: "speed", position: [10, 0, 40] },
      { id: "p5", perkId: "revive", position: [10, 0, 20] },
    ],
    pack: [40, 0, 30],
    repairZones: [
      { id: "rz1", position: [10, 0, 30], cost: 500 },
      { id: "rz2", position: [56, 0, 20], cost: 800 },
    ],
    statusLights: [
      { id: "sl1", position: [-22, 0, -14], color: [90, 255, 120], range: 18, label: "SECURITY" },
      { id: "sl2", position: [66, 0, -14], color: [90, 255, 120], range: 18, label: "EXIT" },
      { id: "sl3", position: [4, 0, 44], color: [255, 90, 90], range: 18, label: "RESTRICTED" },
    ],
  },
};

// ---------------------------------------------------------------------------
//  Offline text derivation (zero-key fallback)
//
//  Reads theme/goal signals out of the user's prompt and applies small aspect
//  deltas to the reference spec. These are aspect nudges — a palette, a win
//  condition, a pacing knob — NOT shipped games. With a DeepSeek key (or a
//  --spec import) the same prompt produces a fully novel design instead.
// ---------------------------------------------------------------------------

const TEXT_RULES = [
  {
    keys: ["neon", "sci-fi", "sci fi", "cyber", "futuristic", "space", "alien", "arena", "grid", "synth"],
    delta: {
      styleGuide: { material: "neon", eyeColor: [0, 255, 220] },
      theme: {
        accent: [0, 255, 220], danger: [255, 40, 120], success: [120, 255, 180],
        bg: [8, 6, 18], panel: [16, 12, 30], panelLight: [28, 22, 48],
        text: [235, 240, 255], textDim: [150, 150, 200], overlay: [4, 2, 10],
      },
      map: {
        theme: {
          accent: [0, 255, 220], fog: [8, 6, 24],
          lighting: {
            ambient: [24, 14, 48], outdoor: [34, 20, 66], shiftTop: [120, 60, 220],
            shiftBottom: [6, 2, 16], brightness: 1.5, clockTime: 0.4, exposure: 0.15,
            fogStart: 30, fogEnd: 180, atmosphereDensity: 0.5, atmosphereGlare: 0.6,
            atmosphereHaze: 1.8, skyColor: [10, 6, 30],
          },
        },
      },
    },
  },
  {
    keys: ["extract", "loot", "raid", "heist", "escape", "objective", "mercenary", "stash"],
    delta: {
      tagline: "Raid the zone. Fill the case. Extract or die trying.",
      rounds: { winRound: 5, bossEvery: 2 },
      points: { starting: 1500, perKill: 90 },
    },
  },
  {
    keys: ["tower", "defense", "defend", "siege", "wall"],
    delta: {
      tagline: "The wall is all that stands between them and you.",
      rounds: { baseEnemies: 8, maxEnemies: 40, intermissionSeconds: 15 },
      points: { perRound: 800, starting: 300 },
    },
  },
  {
    keys: ["cartoon", "fun", "colorful", "kids", "bright", "cute"],
    delta: {
      styleGuide: { material: "cartoon" },
      theme: {
        accent: [255, 120, 220], danger: [255, 90, 90], success: [120, 255, 160],
        bg: [24, 20, 40], panel: [36, 30, 58], panelLight: [52, 44, 78],
        text: [255, 250, 245], textDim: [190, 180, 200], overlay: [16, 12, 26],
      },
      map: {
        theme: {
          floor: [90, 110, 70], wall: [120, 90, 150], accent: [255, 120, 220],
          fog: [150, 170, 190],
          lighting: {
            ambient: [120, 120, 150], outdoor: [160, 160, 190], shiftTop: [200, 180, 230],
            shiftBottom: [40, 36, 60], brightness: 1.6, clockTime: 12, exposure: 0.2,
            fogStart: 60, fogEnd: 320, atmosphereDensity: 0.2, atmosphereHaze: 0.6,
            skyColor: [120, 170, 230],
          },
        },
      },
    },
  },
  {
    keys: ["dark", "horror", "night", "undead", "zombie", "ghost", "apocalyp"],
    delta: {
      styleGuide: { material: "grunge" },
      map: {
        theme: {
          lighting: {
            ambient: [22, 22, 30], outdoor: [30, 30, 40], shiftTop: [60, 60, 80],
            shiftBottom: [6, 6, 10], brightness: 0.9, clockTime: 0.5, exposure: 0,
            fogStart: 30, fogEnd: 170, atmosphereDensity: 0.45, atmosphereHaze: 1.6,
            skyColor: [12, 12, 18],
          },
        },
      },
    },
  },
  {
    keys: ["obby", "parkour", "obstacle", "jump", "climb", "finish", "checkpoint"],
    delta: { gameType: "obby" },
  },
  {
    keys: ["tycoon", "business", "empire", "idle", "money", "sim", "simulation"],
    delta: { gameType: "tycoon" },
  },
  {
    keys: ["racing", "race", "race car", "vehicle", "speedway", "drift", "track"],
    delta: { gameType: "racing" },
  },
];

const NAME_STOPWORDS = new Set([
  "a", "an", "the", "make", "build", "create", "game", "of", "with", "and",
  "for", "to", "in", "on", "my", "me", "i", "want", "that", "this", "is",
]);

function deriveName(promptText) {
  const words = promptText
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((w) => w.length > 2 && !NAME_STOPWORDS.has(w));
  const picked = words.slice(0, 3);
  if (picked.length === 0) return null;
  return picked.map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
}

function deriveFromText(promptText) {
  const lower = promptText.toLowerCase();
  // deepMerge is pure (returns a new object) — accumulate the result, or the
  // deltas silently vanish and every offline game ships the reference theme.
  let delta = {};
  for (const rule of TEXT_RULES) {
    if (rule.keys.some((k) => lower.includes(k))) {
      delta = deepMerge(delta, rule.delta);
    }
  }
  if (!delta.name) {
    const name = deriveName(promptText);
    if (name) delta.name = name;
  }
  return delta;
}

// ---------------------------------------------------------------------------
//  Spatial prop manifest
//
//  assets/props.manifest.json holds hand-placed, explicit coordinates for
//  complex props (mystery boxes, wall buys, repair stations, status lights).
//  opencloud.js reads it to know which props need generated 3D models; here
//  we merge it into every generated GameSpec so the runtime builds the map
//  with these exact placements instead of pure procedural math.
// ---------------------------------------------------------------------------

const PROPS_MANIFEST_PATH = path.join(__dirname, "..", "assets", "props.manifest.json");
const PROPS_GROUPS = ["wallBuys", "boxes", "perks", "repairZones", "statusLights"];

function applyPropsManifest(spec) {
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(PROPS_MANIFEST_PATH, "utf8"));
  } catch {
    return spec; // no manifest — keep the generated layout
  }
  if (!spec.map || !manifest.map) return spec;

  // The manifest is tuned to the default roster. Never reference weapon/perk
  // ids that don't exist in this spec, or wall buys would silently no-op and
  // perk machines would sell nothing.
  const weaponIds = new Set((spec.weapons || []).map((w) => w.id));
  const perkIds = new Set((spec.perks || []).map((p) => p.id));

  for (const key of PROPS_GROUPS) {
    if (!Array.isArray(manifest.map[key]) || manifest.map[key].length === 0) continue;
    const merged = manifest.map[key]
      .filter((entry) => {
        if (key === "wallBuys") return weaponIds.has(entry.weaponId);
        if (key === "perks") return perkIds.has(entry.perkId);
        return true;
      })
      .map((entry) => {
        const clean = { ...entry };
        // Manifest edits bypass the earlier sanitize pass — clamp again here.
        if (key === "repairZones") clean.cost = clampNum(clean.cost, 0, 100000, 500);
        if (key === "statusLights") {
          clean.color = sanitizeColor(clean.color);
          clean.range = clampNum(clean.range, 1, 100, 18);
        }
        // Manifest-only metadata (model upload slots, uploaded ids) is not
        // part of the runtime spec.
        delete clean.model;
        delete clean.rbxassetId;
        return clean;
      });
    if (merged.length > 0) spec.map[key] = merged;
  }
  if (Array.isArray(manifest.map.spawn)) spec.map.spawn = manifest.map.spawn;
  if (Array.isArray(manifest.map.pack)) spec.map.pack = manifest.map.pack;
  return spec;
}

function deepMerge(base, override) {
  if (Array.isArray(base) && Array.isArray(override)) return override;
  if (override && typeof override === "object" && base && typeof base === "object") {
    const out = { ...base };
    for (const [k, v] of Object.entries(override)) out[k] = deepMerge(base[k], v);
    return out;
  }
  return override === undefined ? base : override;
}

function slugify(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "") || "game";
}

// ---------------------------------------------------------------------------
//  Structured-output validation + sanitization
//
//  The designer returns free JSON; before it is compiled into --!strict Luau
//  we validate the shape and clamp every numeric field to sane ranges, so a
//  hallucinated comma or a negative damage value can never break a build.
// ---------------------------------------------------------------------------

function clampNum(value, min, max, fallback) {
  if (typeof value !== "number" || !isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

function sanitizeColor(value) {
  if (!Array.isArray(value) || value.length < 3) return [128, 128, 128];
  return value.slice(0, 3).map((c) => clampNum(c, 0, 255, 128));
}

function sanitizeSpec(spec) {
  const out = { ...spec };
  const warnings = [];

  out.name = typeof out.name === "string" && out.name.trim() ? out.name : "Untitled Game";
  out.tagline = typeof out.tagline === "string" ? out.tagline : "";
  out.gameType = typeof out.gameType === "string" && out.gameType.trim() ? out.gameType.trim().toLowerCase() : "wave";

  const rounds = (out.rounds = { ...(out.rounds || {}) });
  rounds.baseEnemies = clampNum(rounds.baseEnemies, 1, 200, 5);
  rounds.enemiesPerRound = clampNum(rounds.enemiesPerRound, 0, 50, 2);
  rounds.maxEnemies = clampNum(rounds.maxEnemies, 1, 400, 26);
  rounds.intermissionSeconds = clampNum(rounds.intermissionSeconds, 1, 120, 10);
  rounds.playerScaleCap = clampNum(rounds.playerScaleCap, 1, 10, 3);
  rounds.bossEvery = clampNum(rounds.bossEvery, 1, 20, 5);
  rounds.barricadeHp = clampNum(rounds.barricadeHp, 0, 5000, 300);
  rounds.winRound = clampNum(rounds.winRound, 0, 100, 0);

  const player = (out.player = { ...(out.player || {}) });
  player.maxHealth = clampNum(player.maxHealth, 1, 10000, 100);
  player.regenDelay = clampNum(player.regenDelay, 0, 60, 6);
  player.regenRate = clampNum(player.regenRate, 0, 500, 12);
  player.bleedoutSeconds = clampNum(player.bleedoutSeconds, 1, 300, 45);
  player.reviveSeconds = clampNum(player.reviveSeconds, 0.5, 30, 3);
  player.reviveRange = clampNum(player.reviveRange, 1, 50, 10);

  const points = (out.points = { ...(out.points || {}) });
  points.perHit = clampNum(points.perHit, 0, 1000, 10);
  points.perKill = clampNum(points.perKill, 0, 10000, 60);
  points.perHeadshotBonus = clampNum(points.perHeadshotBonus, 0, 5000, 30);
  points.perRound = clampNum(points.perRound, 0, 50000, 500);
  points.starting = clampNum(points.starting, 0, 100000, 0);

  out.mysteryBoxCost = clampNum(out.mysteryBoxCost, 0, 100000, 950);
  out.packCost = clampNum(out.packCost, 0, 500000, 5000);

  if (!Array.isArray(out.weapons) || out.weapons.length === 0) {
    warnings.push("weapons missing/empty — using reference roster");
    out.weapons = DEFAULTS.weapons;
  } else {
    out.weapons = out.weapons.map((w) => {
      const weapon = { ...(DEFAULTS.weapons[0] || {}), ...w };
      weapon.damage = clampNum(weapon.damage, 1, 100000, 28);
      weapon.headshotMultiplier = clampNum(weapon.headshotMultiplier, 1, 10, 1.5);
      weapon.roundsPerSecond = clampNum(weapon.roundsPerSecond, 0.1, 40, 5);
      weapon.magSize = clampNum(weapon.magSize, 0, 10000, 12);
      weapon.reserve = clampNum(weapon.reserve, 0, 100000, 96);
      weapon.reloadTime = clampNum(weapon.reloadTime, 0, 30, 1.5);
      weapon.spread = clampNum(weapon.spread, 0, 1, 0.02);
      weapon.recoil = clampNum(weapon.recoil, 0, 10, 1);
      weapon.range = clampNum(weapon.range, 1, 10000, 250);
      weapon.pellets = clampNum(weapon.pellets, 1, 16, 1);
      weapon.wallBuyCost = clampNum(weapon.wallBuyCost, 0, 100000, 1000);
      weapon.ammoCost = clampNum(weapon.ammoCost, 0, 100000, 400);
      weapon.color = sanitizeColor(weapon.color);
      weapon.packTiers = Array.isArray(weapon.packTiers) ? weapon.packTiers : [];
      return weapon;
    });
  }

  if (!Array.isArray(out.enemies) || out.enemies.length === 0) {
    warnings.push("enemies missing/empty — using reference roster");
    out.enemies = DEFAULTS.enemies;
  } else {
    out.enemies = out.enemies.map((e) => {
      const enemy = { ...(DEFAULTS.enemies[0] || {}), ...e };
      enemy.baseHealth = clampNum(enemy.baseHealth, 1, 1000000, 100);
      enemy.healthPerRound = clampNum(enemy.healthPerRound, 0, 100000, 14);
      enemy.speed = clampNum(enemy.speed, 1, 80, 12);
      enemy.damage = clampNum(enemy.damage, 1, 10000, 12);
      enemy.attackRate = clampNum(enemy.attackRate, 0.1, 20, 1);
      enemy.points = clampNum(enemy.points, 0, 100000, 60);
      enemy.hitPoints = clampNum(enemy.hitPoints, 1, 100, 10);
      enemy.color = sanitizeColor(enemy.color);
      enemy.scale = clampNum(enemy.scale, 0.1, 10, 1);
      enemy.unlockRound = clampNum(enemy.unlockRound, 1, 100, 1);
      enemy.spawnWeight = clampNum(enemy.spawnWeight, 0, 100, 10);
      return enemy;
    });
  }

  out.perks = Array.isArray(out.perks) && out.perks.length > 0 ? out.perks.map((p) => ({ ...p, color: sanitizeColor(p.color) })) : DEFAULTS.perks;

  const map = (out.map = { ...(out.map || {}) });
  map.name = typeof map.name === "string" ? map.name : out.name;
  map.theme = { ...(map.theme || {}) };
  for (const key of ["floor", "wall", "accent", "fog"]) map.theme[key] = sanitizeColor(map.theme[key]);
  // Lighting profile is always complete: backfill from the reference spec and
  // clamp every numeric so a partial --spec file or a wild value (clockTime 99,
  // brightness -5) can never compile into broken Luau.
  const light = { ...DEFAULTS.map.theme.lighting, ...(map.theme.lighting || {}) };
  for (const key of ["ambient", "outdoor", "shiftTop", "shiftBottom", "skyColor"]) {
    light[key] = sanitizeColor(light[key]);
  }
  light.brightness = clampNum(light.brightness, 0, 3, 1.15);
  light.clockTime = clampNum(light.clockTime, 0, 24, 19.5);
  light.exposure = clampNum(light.exposure, -2, 2, 0);
  light.fogStart = clampNum(light.fogStart, 0, 500, 40);
  light.fogEnd = clampNum(light.fogEnd, 1, 1000, 220);
  light.atmosphereDensity = clampNum(light.atmosphereDensity, 0, 2, 0.3);
  light.atmosphereOffset = clampNum(light.atmosphereOffset, 0, 1, 0.1);
  light.atmosphereGlare = clampNum(light.atmosphereGlare, 0, 2, 0.25);
  light.atmosphereHaze = clampNum(light.atmosphereHaze, 0, 5, 1.2);
  map.theme.lighting = light;

  map.repairZones =
    Array.isArray(map.repairZones) && map.repairZones.length > 0
      ? map.repairZones.map((r) => ({ ...r, cost: clampNum(r.cost, 0, 100000, 500) }))
      : DEFAULTS.map.repairZones.map((r) => ({ ...r }));
  map.statusLights =
    Array.isArray(map.statusLights) && map.statusLights.length > 0
      ? map.statusLights.map((s) => ({ ...s, color: sanitizeColor(s.color), range: clampNum(s.range, 1, 100, 18) }))
      : DEFAULTS.map.statusLights.map((s) => ({ ...s }));

  // Doors live inside map (matches types.MapSpec + the runtime). Accept a
  // legacy top-level "doors" key from hand-written or older specs.
  if (!Array.isArray(map.doors) && Array.isArray(out.doors)) {
    map.doors = out.doors;
  }
  delete out.doors;

  if (!Array.isArray(map.zones) || map.zones.length < 2) {
    warnings.push("map zones invalid — using reference layout");
    map.zones = DEFAULTS.map.zones;
  }
  // Copy zones so sanitize never mutates the caller's arrays (e.g. a --spec file).
  map.zones = map.zones.map((z) => ({ ...z }));
  map.zones[0].door = null; // the root zone never has a door

  const zonesOk = Array.isArray(map.zones) && map.zones.length > 0;
  const doors = (map.doors = Array.isArray(map.doors) && map.doors.length > 0 ? map.doors : DEFAULTS.map.doors);
  if (zonesOk) {
    const zoneIds = new Set(map.zones.map((z) => z.id));
    map.doors = doors.filter((d) => zoneIds.has(d.from) && zoneIds.has(d.to));
    if (map.doors.length === 0 && map.zones.length > 1) {
      // Rebuild a connected chain from the actual zone order.
      warnings.push("doors did not form a valid chain — building a default chain");
      map.doors = map.zones.slice(1).map((zone, i) => ({
        id: `d${i + 1}`,
        name: `Gate ${i + 1}`,
        cost: 500 + i * 300,
        from: map.zones[i].id,
        to: zone.id,
      }));
    }
  }

  // Engine config blocks are always present; keep user values if sane.
  out.anticheat = { ...DEFAULTS.anticheat, ...(out.anticheat || {}) };
  out.styleGuide = { ...DEFAULTS.styleGuide, ...(out.styleGuide || {}) };
  if (out.styleGuide.eyeColor) out.styleGuide.eyeColor = sanitizeColor(out.styleGuide.eyeColor).slice(0, 3);
  out.net = { ...DEFAULTS.net, ...(out.net || {}) };
  out.net.enemyBatchHz = clampNum(out.net.enemyBatchHz, 1, 20, 5);

  // UI theme tokens always present
  out.theme = { ...DEFAULTS.theme, ...(out.theme || {}) };
  for (const key of ["accent", "danger", "success", "bg", "panel", "panelLight", "text", "textDim", "overlay"]) {
    out.theme[key] = sanitizeColor(out.theme[key]);
  }

  // Explicit spatial placements from the manifest always win over generated
  // coordinates — hand-placed props are the source of truth for map feel.
  applyPropsManifest(out);

  return { spec: out, warnings };
}

async function callDeepSeek(promptText) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("Missing DEEPSEEK_API_KEY.");
  const res = await fetch(DEEPSEEK_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "deepseek-chat",
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: getSystemPrompt() },
        { role: "user", content: promptText },
      ],
      temperature: 0.9,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`DeepSeek failed (${res.status}): ${JSON.stringify(data)}`);
  const content = data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
  if (!content) throw new Error(`DeepSeek returned no content: ${JSON.stringify(data)}`);
  return JSON.parse(content);
}

// Import a hand-written or externally designed spec (e.g. JSON produced by any
// AI chat using pipeline/system_prompt.md as its system prompt).
function loadSpecFile(specFile) {
  let raw;
  try {
    raw = fs.readFileSync(specFile, "utf8");
  } catch (err) {
    throw new Error(`Cannot read spec file: ${specFile} (${err.message})`);
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`Spec file is not valid JSON: ${specFile}`);
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error(`Spec file must be a JSON object: ${specFile}`);
  }
  return deepMerge(DEFAULTS, parsed);
}

async function specFromPrompt(promptText, { offline = false, specFile = null } = {}) {
  if (specFile) {
    const { spec, warnings } = sanitizeSpec(loadSpecFile(specFile));
    for (const warning of warnings) console.warn(`[codegen] ${warning}`);
    return spec;
  }
  if (!offline && process.env.USE_DEEPSEEK !== "false" && process.env.DEEPSEEK_API_KEY) {
    try {
      const designed = await callDeepSeek(promptText);
      const { spec, warnings } = sanitizeSpec(deepMerge(DEFAULTS, designed));
      for (const warning of warnings) console.warn(`[codegen] ${warning}`);
      return spec;
    } catch (err) {
      console.warn(`[codegen] DeepSeek failed (${err.message}); falling back to offline derivation.`);
    }
  } else if (!offline && process.env.USE_DEEPSEEK !== "false" && !process.env.DEEPSEEK_API_KEY) {
    console.warn("[codegen] No DEEPSEEK_API_KEY — using offline text derivation on the reference spec.");
    console.warn("[codegen] For a fully novel design, add a key, use --spec with JSON from any AI chat,");
    console.warn("[codegen] or hand-edit games/<slug>/spec.json and regenerate.");
  }
  const derived = deriveFromText(promptText);
  const { spec, warnings } = sanitizeSpec(deepMerge(DEFAULTS, derived));
  for (const warning of warnings) console.warn(`[codegen] ${warning}`);
  return spec;
}

// ---- Lua emitter ----------------------------------------------------------
// Array values are disambiguated by their key: color fields -> Color3,
// position fields -> Vector3, everything else -> plain tables.

const COLOR_KEYS = new Set([
  "color",
  "floor",
  "wall",
  "accent",
  "fog",
  "danger",
  "success",
  "ambient",
  "outdoor",
  "shiftTop",
  "shiftBottom",
  "skyColor",
  "bg",
  "panel",
  "panelLight",
  "text",
  "textDim",
  "overlay",
]);
const VECTOR_KEYS = new Set(["center", "size", "spawn", "position", "pack"]);

function luaValue(v, indent, mode) {
  const pad = "    ".repeat(indent);
  if (v === null || v === undefined) return "nil";
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(Math.round(v * 1000) / 1000);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "string") return `"${v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  if (Array.isArray(v)) {
    const numeric = v.every((x) => typeof x === "number");
    if (mode === "color" && numeric && v.length === 3) {
      return `Color3.fromRGB(${v.map((x) => Math.round(x)).join(", ")})`;
    }
    if (mode === "vector3" && numeric && (v.length === 2 || v.length === 3)) {
      const y = v[1] || 0;
      const z = v[2] || 0;
      return `Vector3.new(${v[0]}, ${y}, ${z})`;
    }
    if (v.length === 0) return "{}";
    return "{\n" + v.map((x) => pad + "    " + luaValue(x, indent + 1)).join(",\n") + ",\n" + pad + "}";
  }
  if (typeof v === "object") {
    const keys = Object.keys(v);
    if (keys.length === 0) return "{}";
    const body = keys
      .map((k) => {
        const childMode = COLOR_KEYS.has(k) ? "color" : VECTOR_KEYS.has(k) ? "vector3" : "plain";
        const key = /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `["${k}"]`;
        return `        ${pad}    ${key} = ${luaValue(v[k], indent + 1, childMode)}`;
      })
      .join(",\n");
    return "{\n" + body + ",\n" + pad + "}";
  }
  return "nil";
}

function emitConfig(spec) {
  return `--!strict
-- ============================================================================
--  GAME SPEC — generated by the RBLX Operator pipeline.
--  This file IS the game: every runtime module reads balance, systems, map,
--  lighting and UI theme from this table. Regenerate it with:
--      node pipeline/bridge.js newgame "<your game idea>"
-- ============================================================================

local GameSpec = ${luaValue(spec, 0)}

return GameSpec
`;
}

function writeGameSpec(spec) {
  const slug = slugify(spec.name || "game");
  fs.mkdirSync(path.join(GAMES_DIR, slug), { recursive: true });
  fs.writeFileSync(path.join(GAMES_DIR, slug, "spec.json"), JSON.stringify(spec, null, 2) + "\n");
  fs.writeFileSync(CONFIG_PATH, emitConfig(spec));
  return {
    slug,
    specPath: path.join(GAMES_DIR, slug, "spec.json"),
    configPath: CONFIG_PATH,
    weapons: (spec.weapons || []).length,
    enemies: (spec.enemies || []).length,
    perks: (spec.perks || []).length,
    doors: (spec.map && spec.map.doors || []).length,
    zones: (spec.map && spec.map.zones || []).length,
  };
}

module.exports = {
  specFromPrompt,
  writeGameSpec,
  emitConfig,
  deepMerge,
  sanitizeSpec,
  deriveFromText,
  getSystemPrompt,
  slugify,
  SYSTEM_PROMPT_PATH,
  DEFAULTS,
  applyPropsManifest,
  PROPS_MANIFEST_PATH,
};

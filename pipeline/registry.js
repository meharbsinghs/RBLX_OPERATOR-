"use strict";

/**
 * Generated-asset registry. Tracks every Meshy-generated model so games can
 * reference them by id. Lives at assets/registry.json (committed, so the
 * history of generated assets is part of the repo).
 */

const fs = require("fs");
const path = require("path");

const REGISTRY_PATH = path.join(__dirname, "..", "assets", "registry.json");

function load() {
  try {
    const parsed = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    if (parsed && Array.isArray(parsed.entries)) return parsed;
    return { version: 1, entries: [] };
  } catch {
    return { version: 1, entries: [] };
  }
}

function save(registry) {
  fs.mkdirSync(path.dirname(REGISTRY_PATH), { recursive: true });
  fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
}

function addEntry(record) {
  const registry = load();
  const rel = (p) => (p ? path.relative(path.join(__dirname, ".."), p).replace(/\\/g, "/") : null);
  registry.entries.unshift({
    id: `asset-${Date.now()}`,
    name: record.name,
    kind: record.kind || "prop",
    prompt: record.prompt || "",
    glb: rel(record.glb),
    texture: rel(record.texture),
    thumbnail: record.thumbnail || null,
    rbxassetId: record.rbxassetId || null,
    createdAt: new Date().toISOString(),
    usedBy: null,
  });
  save(registry);
  return registry.entries[0];
}

function list(kind) {
  const entries = load().entries;
  return kind ? entries.filter((e) => e.kind === kind) : entries;
}

function markUsed(id, usage) {
  const registry = load();
  const entry = registry.entries.find((e) => e.id === id);
  if (entry) {
    entry.usedBy = usage;
    save(registry);
  }
  return entry;
}

module.exports = { load, save, addEntry, list, markUsed, REGISTRY_PATH };

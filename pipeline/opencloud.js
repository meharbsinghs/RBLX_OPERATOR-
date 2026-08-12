"use strict";

/**
 * Roblox Open Cloud Assets client.
 *
 * Uploads generated 3D models (.glb) directly to Roblox from the pipeline, so
 * a generated asset gets a live rbxassetid:// link with ZERO manual Studio
 * importing. This removes the last human step from the asset loop.
 *
 * Docs:  https://create.roblox.com/docs/cloud/open-cloud/assets
 * Flow:  multipart POST /assets/v1/assets  ->  operationId
 *     -> poll GET /assets/v1/operations/{operationId} until done
 *     -> assetId  ->  rbxassetid://<assetId>
 *
 * Env:   OPEN_CLOUD_API_KEY  (Open Cloud API key with Assets:Write scope)
 *        OPEN_CLOUD_CREATOR_ID (optional — only set when key lacks a creator scope)
 */

const fs = require("fs");
const path = require("path");

const BASE_URL = "https://apis.roblox.com";
const MANIFEST_PATH = path.join(__dirname, "..", "assets", "props.manifest.json");
const MANIFEST_GROUPS = ["wallBuys", "boxes", "perks", "repairZones", "statusLights"];

// ---------------------------------------------------------------------------
//  Spatial prop manifest (assets/props.manifest.json)
//
//  Explicit coordinates for hand-placed map assets. This module reads it so
//  `bridge.js props --sync` knows which props need generated 3D models, and
//  writes uploaded rbxassetId links straight back into the manifest — making
//  the map's "hero" props live Roblox assets with zero Studio importing.
// ---------------------------------------------------------------------------

function loadPropsManifest() {
  try {
    const parsed = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8"));
    if (parsed && parsed.map) return parsed;
    return { version: 1, description: "", map: {} };
  } catch {
    return { version: 1, description: "", map: {} };
  }
}

function savePropsManifest(manifest) {
  fs.mkdirSync(path.dirname(MANIFEST_PATH), { recursive: true });
  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + "\n");
}

/**
 * Flatten the manifest into a list of prop placements (one per entry).
 * @returns {{group:string, id:string, position:number[], model:string|null, rbxassetId:string|null}[]}
 */
function listProps(manifest) {
  const map = manifest.map || {};
  const out = [];
  for (const group of MANIFEST_GROUPS) {
    for (const entry of map[group] || []) {
      out.push({
        group,
        id: entry.id || "?",
        position: Array.isArray(entry.position) ? entry.position : [],
        model: entry.model || null,
        rbxassetId: entry.rbxassetId || null,
      });
    }
  }
  return out;
}

/**
 * Record an uploaded rbxassetId back on a manifest entry. Returns true on success.
 */
function setPropAssetId(manifest, group, id, rbxassetId) {
  for (const entry of (manifest.map && manifest.map[group]) || []) {
    if (entry.id === id) {
      entry.rbxassetId = rbxassetId;
      return true;
    }
  }
  return false;
}

function apiKey() {
  const key = process.env.OPEN_CLOUD_API_KEY;
  if (!key) {
    throw new Error("Missing OPEN_CLOUD_API_KEY in environment. Copy .env.example to .env and add your Open Cloud key.");
  }
  return key;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Start an asset upload. Returns { operationId }.
 */
async function uploadModel({ filePath, displayName, description = "", assetType = "Model" }) {
  const key = apiKey();
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }
  const buf = fs.readFileSync(filePath);
  const fileName = path.basename(filePath);

  const request = {
    assetType,
    displayName: displayName || fileName.replace(/\.[^.]+$/, ""),
    description: String(description || "").slice(0, 1000),
  };
  if (process.env.OPEN_CLOUD_CREATOR_ID) {
    request.creationContext = { creator: { userId: process.env.OPEN_CLOUD_CREATOR_ID } };
  }

  const form = new FormData();
  form.append("request", JSON.stringify(request));
  form.append("fileContent", new Blob([buf]), fileName);

  const res = await fetch(`${BASE_URL}/assets/v1/assets`, {
    method: "POST",
    headers: { "x-api-key": key },
    body: form,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`Open Cloud upload failed (${res.status}): ${JSON.stringify(data)}`);
  }
  const operationId = data.operationId || data.id;
  if (!operationId) {
    throw new Error(`Open Cloud response missing operationId: ${JSON.stringify(data)}`);
  }
  return { operationId };
}

/**
 * Poll an upload operation until it is done. Returns the final response object.
 */
async function pollOperation(operationId, { intervalMs = 1000, timeoutMs = 120000 } = {}) {
  const started = Date.now();
  for (;;) {
    const res = await fetch(`${BASE_URL}/assets/v1/operations/${encodeURIComponent(operationId)}`, {
      headers: { "x-api-key": apiKey() },
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(`Open Cloud operation poll failed (${res.status}): ${JSON.stringify(data)}`);
    }
    if (data.done) {
      return data.response || {};
    }
    if (Date.now() - started > timeoutMs) {
      throw new Error(`Open Cloud operation ${operationId} timed out after ${Math.round(timeoutMs / 1000)}s.`);
    }
    await sleep(intervalMs);
  }
}

/**
 * End-to-end upload: multipart PUT -> poll -> rbxassetid link.
 * @returns {{ assetId: string, assetUri: string }}
 */
async function uploadModelAndPoll(opts) {
  const { operationId } = await uploadModel(opts);
  const response = await pollOperation(operationId);
  const assetUri = response.assetUri || (response.assetId ? `rbxassetid://${response.assetId}` : null);
  if (!assetUri) {
    throw new Error(`Open Cloud operation completed without an asset id: ${JSON.stringify(response)}`);
  }
  const assetId = assetUri.replace("rbxassetid://", "");
  return { assetId, assetUri };
}

module.exports = {
  uploadModel,
  pollOperation,
  uploadModelAndPoll,
  BASE_URL,
  MANIFEST_PATH,
  loadPropsManifest,
  savePropsManifest,
  listProps,
  setPropAssetId,
};

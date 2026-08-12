"use strict";

/**
 * Meshy text-to-3D client (api.meshy.ai, v2).
 * Docs: https://docs.meshy.ai
 *
 * Flow: create task -> poll until SUCCEEDED -> download GLB (+ albedo texture)
 * into assets/generated and hand the record to registry.js.
 */

const fs = require("fs");
const path = require("path");
const opencloud = require("./opencloud");

const BASE_URL = "https://api.meshy.ai";
const DONE = new Set(["SUCCEEDED", "FAILED", "EXPIRED", "CANCELED"]);

function apiKey() {
  const key = process.env.MESHY_API_KEY;
  if (!key) {
    throw new Error(
      "Missing MESHY_API_KEY in environment. Copy .env.example to .env and add your key (https://www.meshy.ai)."
    );
  }
  return key;
}

async function createTask({
  prompt,
  artStyle = process.env.MESHY_ART_STYLE || "low-poly",
  negativePrompt = "disfigured, blurry, low quality, extra limbs, watermark, text",
  topology = "triangle",
  targetPolycount = Number(process.env.MESHY_TARGET_POLYCOUNT || 4000),
  mode = "preview",
  seed,
}) {
  if (!prompt || typeof prompt !== "string" || !prompt.trim()) {
    throw new Error("createTask requires a non-empty text prompt.");
  }
  const body = {
    prompt,
    art_style: artStyle,
    negative_prompt: negativePrompt,
    topology,
    target_polycount: targetPolycount,
    mode,
  };
  if (seed !== undefined) body.seed = seed;

  const res = await fetch(`${BASE_URL}/v2/text-to-3d`, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey()}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`Meshy create-task failed (${res.status}): ${JSON.stringify(data)}`);
  }
  const taskId = data.result || data.id;
  if (!taskId) throw new Error(`Meshy response missing task id: ${JSON.stringify(data)}`);
  return taskId;
}

async function getTask(taskId) {
  const res = await fetch(`${BASE_URL}/v2/text-to-3d/${encodeURIComponent(taskId)}`, {
    headers: { Authorization: `Bearer ${apiKey()}` },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Meshy get-task failed (${res.status}): ${JSON.stringify(data)}`);
  return data;
}

async function waitForTask(taskId, { intervalMs = 5000, timeoutMs = 10 * 60 * 1000, onProgress } = {}) {
  const started = Date.now();
  for (;;) {
    const task = await getTask(taskId);
    const status = task.status || "UNKNOWN";
    if (onProgress) onProgress(status, task);
    if (status === "SUCCEEDED") return task;
    if (DONE.has(status)) {
      throw new Error(`Meshy task ${taskId} ended with status ${status}: ${task.error_message || "no details"}`);
    }
    if (Date.now() - started > timeoutMs) {
      throw new Error(`Meshy task ${taskId} timed out after ${Math.round(timeoutMs / 1000)}s.`);
    }
    await sleep(intervalMs);
  }
}

async function download(url, dest) {
  if (!url) throw new Error("No download URL provided.");
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed (${res.status}) for ${url}`);
  const buf = Buffer.from(await res.arrayBuffer());
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, buf);
  return dest;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * End-to-end asset generation: prompt -> task -> poll -> download GLB + albedo.
 * @returns {{taskId:string, status:string, name:string, kind:string, prompt:string, glb:string|null, texture:string|null}}
 */
async function generate3DAsset(promptText, { name, kind = "prop", outDir = path.join(__dirname, "..", "assets", "generated") } = {}) {
  const taskId = await createTask({ prompt: promptText });
  const task = await waitForTask(taskId, {
    onProgress: (status) => console.log(`  [meshy] ${taskId} -> ${status}`),
  });

  const urls = task.model_urls || {};
  const textureUrl = (task.texture_urls || {}).base_color;
  const slug =
    (name || promptText).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "") || "asset";
  const stamp = Date.now();

  const glb = urls.glb ? await download(urls.glb, path.join(outDir, `${slug}-${stamp}.glb`)) : null;
  const texture = textureUrl
    ? await download(textureUrl, path.join(outDir, `${slug}-${stamp}-albedo.png`))
    : null;

  // Optional: push straight into Roblox via Open Cloud, no Studio importing.
  let rbxassetId = null;
  if (glb && process.env.OPEN_CLOUD_API_KEY) {
    try {
      const uploaded = await opencloud.uploadModelAndPoll({
        filePath: glb,
        displayName: slug,
        description: promptText.slice(0, 200),
      });
      rbxassetId = uploaded.assetUri;
      console.log(`  [opencloud] uploaded to Roblox: ${uploaded.assetUri}`);
    } catch (err) {
      console.warn(`  [opencloud] upload skipped (${err.message}) — asset stays local.`);
    }
  }

  return {
    taskId,
    status: task.status,
    name: slug,
    kind,
    prompt: promptText,
    glb,
    texture,
    thumbnail: task.thumbnail_url || null,
    rbxassetId,
  };
}

module.exports = { createTask, getTask, waitForTask, download, generate3DAsset, BASE_URL };

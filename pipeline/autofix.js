"use strict";

/**
 * Runtime-log -> DeepSeek hot-fix loop.
 *
 * After a playtest, copy the Roblox output (or a .log file) into logs/ and run
 * `bridge.js fix --log logs/runtime.log`. This module:
 *   1. Parses stack traces (`Script '...', Line N - message`) from the log.
 *   2. Maps Roblox instance paths back to repo files (src/server/combat.luau …).
 *   3. Sends each broken file + its errors to DeepSeek, which returns a
 *      corrected full file.
 *   4. Writes the fix back (keeping a .bak) so the loop closes: play -> crash
 *      -> fix -> rebuild. No manual debugging required.
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

/**
 * Extract { instancePath, line, message } tuples from a Roblox output log.
 */
function parseLog(logPath) {
  const text = fs.readFileSync(logPath, "utf8");
  const errors = [];
  // Matches:  Script 'ServerScriptService.RobloxOperator.server.enemies', Line 82 - message
  const re = /Script '([^']+)',\s*Line (\d+)(?:\s*-\s*(.*))?/g;
  let match;
  while ((match = re.exec(text))) {
    errors.push({
      instancePath: match[1].trim(),
      line: parseInt(match[2], 10),
      message: (match[3] || "").trim().split("\n")[0],
    });
  }
  return errors;
}

/**
 * Map a Roblox instance path to a repo file path, or null.
 */
function mapToFile(instancePath) {
  let rel = instancePath;
  const prefixes = [
    "StarterPlayer.StarterPlayerScripts.",
    "StarterPlayerScripts.",
    "ServerScriptService.",
    "ReplicatedStorage.",
    "RBLXOperator.",
  ];
  for (const prefix of prefixes) {
    if (rel.startsWith(prefix)) {
      rel = rel.slice(prefix.length);
      break;
    }
  }
  const parts = rel.split(".").filter((p) => p.length > 0);
  if (parts.length < 2) {
    // ReplicatedStorage.<module> -> src/shared/<module>.luau
    const shared = path.join(ROOT, "src", "shared", `${parts[0] || rel}.luau`);
    return fs.existsSync(shared) ? shared : null;
  }
  const top = parts[0];
  if (top !== "server" && top !== "client" && top !== "shared") return null;

  const last = parts[parts.length - 1];
  const fileName =
    last === "init" ? (top === "server" ? "init.server.luau" : "init.client.luau") : `${last}.luau`;
  const dir = path.join(ROOT, "src", top, ...parts.slice(1, -1));
  const full = path.join(dir, fileName);
  return fs.existsSync(full) ? full : null;
}

async function askDeepSeekToFix({ file, description, source }) {
  const key = process.env.DEEPSEEK_API_KEY;
  if (!key) throw new Error("Missing DEEPSEEK_API_KEY (required for autofix).");
  const res = await fetch(DEEPSEEK_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "deepseek-chat",
      messages: [
        {
          role: "system",
          content:
            "You fix bugs in a Roblox Luau codebase. Files use --!strict Luau. Return ONLY the complete corrected file content in a code block. Preserve the existing style and logic; fix the reported errors and their obvious root cause, nothing else.",
        },
        {
          role: "user",
          content: `File: ${file}\nRuntime errors:\n${description}\n\nCurrent content:\n\`\`\`lua\n${source}\n\`\`\``,
        },
      ],
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`DeepSeek autofix failed (${res.status}): ${JSON.stringify(data)}`);
  const content =
    data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
  if (!content) return null;
  const fenced = content.match(/```[a-z]*\n([\s\S]*?)```/);
  const fixed = (fenced ? fenced[1] : content).replace(/\r\n/g, "\n").trimEnd();
  return fixed + "\n";
}

/**
 * Autofix entry point.
 * @returns {{ fixed: number, files: number, errors: number, unfixed: string[] }}
 */
async function autofixLog(logPath, { dryRun = false } = {}) {
  const errors = parseLog(logPath);
  if (errors.length === 0) {
    console.log("[fix] No stack traces found in the log. Make sure it contains lines like:");
    console.log("      Script 'ServerScriptService.server.combat', Line 42 - attempt to index nil ...");
    return { fixed: 0, files: 0, errors: 0, unfixed: [] };
  }
  console.log(`[fix] ${errors.length} error(s) parsed.`);

  const byFile = new Map();
  for (const error of errors) {
    const file = mapToFile(error.instancePath);
    if (file) {
      if (!byFile.has(file)) byFile.set(file, []);
      byFile.get(file).push(error);
    } else {
      console.warn(`[fix] Could not map instance path to a repo file: ${error.instancePath}`);
    }
  }

  let fixed = 0;
  const unfixed = [];
  for (const [file, errs] of byFile) {
    const rel = path.relative(ROOT, file).replace(/\\/g, "/");
    const source = fs.readFileSync(file, "utf8");
    const description = errs.map((e) => `- Line ${e.line}: ${e.message || "runtime error"}`).join("\n");
    try {
      const fixedSource = await askDeepSeekToFix({ file: rel, description, source });
      if (!fixedSource || fixedSource === source) {
        console.log(`[fix] No fix produced for ${rel}`);
        unfixed.push(rel);
        continue;
      }
      if (dryRun) {
        console.log(`[fix] (dry-run) would patch ${rel}`);
      } else {
        fs.writeFileSync(`${file}.bak`, source);
        fs.writeFileSync(file, fixedSource);
        console.log(`[fix] Patched ${rel} (backup ${path.basename(file)}.bak)`);
      }
      fixed += 1;
    } catch (err) {
      console.error(`[fix] ${rel} failed: ${err.message}`);
      unfixed.push(rel);
    }
  }
  return { fixed, files: byFile.size, errors: errors.length, unfixed };
}

module.exports = { autofixLog, parseLog, mapToFile };

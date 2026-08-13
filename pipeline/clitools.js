"use strict";

/**
 * Windows-safe CLI helpers, shared by bridge.js and the opencode operator.
 *
 * npm installs CLI packages as .cmd shims on Windows; Node's spawnSync cannot
 * execute those directly. These helpers resolve the *real* binary — for an npm
 * shim we read the shim text and follow its %dp0%-relative path to the actual
 * .exe — so spawns behave identically on Windows and POSIX.
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

/** Find a CLI on PATH (Windows: also .cmd/.exe/.bat candidates). Returns an absolute path or null. */
function which(name) {
  // Windows PATHEXT resolves .EXE before .CMD — mirror that order.
  const candidates =
    process.platform === "win32"
      ? [name + ".exe", name + ".cmd", name + ".bat", name]
      : [name];
  const paths = (process.env.PATH || "").split(path.delimiter).filter(Boolean);
  for (const c of candidates) {
    if (c.includes("/") || c.includes("\\")) {
      try {
        fs.accessSync(c);
        return c;
      } catch {
        /* keep looking */
      }
      continue;
    }
    for (const p of paths) {
      const full = path.join(p, c);
      try {
        fs.accessSync(full);
        return full;
      } catch {
        /* keep looking */
      }
    }
  }
  return null;
}

/** Follow an npm .cmd shim to the real binary path. Returns null if not a shim. */
function shimTarget(cmdPath) {
  let txt = "";
  try {
    txt = fs.readFileSync(cmdPath, "utf8");
  } catch {
    return null;
  }
  const dir = path.dirname(cmdPath);
  // npm >= 7 shims point at a real binary: an .exe (opencode) or a .js run by
  // node (e.g. a CLI whose bin entry is a script). Match both.
  const tokenRe = /"([^"]*(?:%dp0%|%~dp0)[^"]*\.(?:exe|cmd|bat|js))"/gi;
  const plainRe = /"([^"]+\.(?:exe|js))"/g;
  let m;
  let target = null;
  while ((m = tokenRe.exec(txt))) target = m[1];
  if (!target) {
    while ((m = plainRe.exec(txt))) target = m[1];
  }
  if (!target) return null;
  target = target.replace(/%dp0%/gi, dir + path.sep).replace(/%~dp0/gi, dir + path.sep);
  target = path.resolve(target);
  return fs.existsSync(target) ? target : null;
}

/**
 * spawnSync a CLI that may be an npm .cmd shim. Returns the spawnSync result.
 * .js shim targets are run through the current node binary.
 * @param {string} bin   resolved path from which() (or any path)
 * @param {string[]} args
 * @param {object} opts  passed through to spawnSync
 */
function spawnCli(bin, args, opts = {}) {
  let target = bin;
  if (process.platform === "win32" && /\.(cmd|bat)$/i.test(bin)) {
    const t = shimTarget(bin);
    if (t) target = t;
    // else: leave bin as-is; spawnSync can run .cmd/.bat files via cmd.exe on
    // modern Node, and the fallback below is only reached for exotic shims.
  }
  if (/\.[j]s$/i.test(target)) {
    return spawnSync(process.execPath, [target, ...args], opts);
  }
  return spawnSync(target, args, opts);
}

module.exports = { which, shimTarget, spawnCli };

"use strict";

/**
 * RBLX Operator Studio — desktop console for the RBLX Operator engine.
 *
 * The app bundles the whole engine (extraResources -> resources/operator) and
 * runs the pipeline on Electron's OWN bundled Node runtime, so end users need
 * nothing installed except Roblox Studio. In dev (`npm run app:start`) it
 * operates on the repo itself so edits flow straight back into the source.
 *
 * Key trick: pipeline scripts are spawned as
 *     process.execPath <script>   with env ELECTRON_RUN_AS_NODE=1
 * which makes Electron run as a plain Node binary — no system node needed.
 */

const { app, BrowserWindow, ipcMain, dialog, shell } = require("electron");
const { spawn, spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

let win = null;
let child = null;
let busy = false;
let cachedRoot = null;

/* ------------------------------------------------------------------ */
/* Root resolution: dev repo vs packaged per-user workspace            */
/* ------------------------------------------------------------------ */

function bundledOperatorDir() {
  return path.join(process.resourcesPath, "operator");
}

function isPackaged() {
  return fs.existsSync(bundledOperatorDir());
}

function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const name of fs.readdirSync(from)) {
    const src = path.join(from, name);
    const dst = path.join(to, name);
    if (fs.statSync(src).isDirectory()) copyDir(src, dst);
    else fs.copyFileSync(src, dst);
  }
}

function seedWorkspace() {
  // Packaged apps cannot write into the install dir (Program Files / temp for
  // portable). Seed a per-user workspace; games, .env and logs live there.
  const ws = path.join(app.getPath("userData"), "workspace");
  const marker = path.join(ws, ".app-version");
  const hasEngine = fs.existsSync(path.join(ws, "pipeline", "bridge.js"));
  if (!hasEngine) {
    copyDir(bundledOperatorDir(), ws);
  } else if (!fs.existsSync(marker) || fs.readFileSync(marker, "utf8") !== app.getVersion()) {
    // App upgraded: refresh the engine code but PRESERVE user data
    // (games/, .env, logs/, .git, the generated .rbxl).
    const keep = new Set(["games", ".env", "logs", ".git", ".app-version"]);
    for (const name of fs.readdirSync(bundledOperatorDir())) {
      if (keep.has(name)) continue;
      const src = path.join(bundledOperatorDir(), name);
      const dst = path.join(ws, name);
      if (fs.statSync(src).isDirectory()) copyDir(src, dst);
      else fs.copyFileSync(src, dst);
    }
  }
  fs.writeFileSync(marker, app.getVersion());
  return ws;
}

function repoRoot() {
  if (cachedRoot) return cachedRoot;
  if (process.env.ROBLOX_OPERATOR_ROOT) cachedRoot = process.env.ROBLOX_OPERATOR_ROOT;
  else if (isPackaged()) cachedRoot = seedWorkspace();
  else cachedRoot = path.join(__dirname, ".."); // dev: the repo itself
  return cachedRoot;
}

function parseEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && out[m[1]] === undefined) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return out;
}

function updateEnvFile(file, updates) {
  const keys = Object.keys(updates);
  const lines = fs.existsSync(file)
    ? fs.readFileSync(file, "utf8").split(/\r?\n/)
    : [];
  for (const key of keys) {
    const re = new RegExp(`^\\s*${key}\\s*=`);
    const idx = lines.findIndex((l) => re.test(l));
    const val = updates[key] || "";
    if (idx !== -1) lines[idx] = `${key}=${val}`;
    else lines.push(`${key}=${val}`);
  }
  fs.writeFileSync(file, lines.join("\n") + "\n");
}

/* ------------------------------------------------------------------ */
/* Child process plumbing (streaming to the renderer console)          */
/* ------------------------------------------------------------------ */

function emit(text, stream) {
  if (win && !win.isDestroyed()) win.webContents.send("operator:output", { stream, text });
}

function runChild(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    if (busy) {
      resolve({ ok: false, code: -1, error: "Another task is already running." });
      return;
    }
    busy = true;
    let p;
    try {
      p = spawn(cmd, args, {
        cwd: opts.cwd || repoRoot(),
        env: opts.env || process.env,
        shell: false,
        windowsHide: true,
      });
    } catch (err) {
      busy = false;
      resolve({ ok: false, code: -1, error: err.message });
      return;
    }
    child = p;
    p.stdout.on("data", (d) => emit(d.toString(), "out"));
    p.stderr.on("data", (d) => emit(d.toString(), "err"));
    p.on("error", (err) => {
      busy = false;
      child = null;
      resolve({ ok: false, code: -1, error: err.message });
    });
    p.on("close", (code) => {
      busy = false;
      child = null;
      resolve({ ok: code === 0, code });
    });
  });
}

// Runs a pipeline script on Electron's bundled Node runtime.
function runPipeline(args, opts = {}) {
  const script = path.join(repoRoot(), "pipeline", "bridge.js");
  const env = { ...process.env, ELECTRON_RUN_AS_NODE: "1", ...parseEnv(path.join(repoRoot(), ".env")) };
  emit(`\n$ node pipeline/bridge.js ${args.join(" ")}\n`, "cmd");
  return runChild(process.execPath, [script, ...args], { ...opts, env });
}

/* ------------------------------------------------------------------ */
/* Window                                                              */
/* ------------------------------------------------------------------ */

function createWindow() {
  win = new BrowserWindow({
    width: 1240,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: "#0b0e14",
    title: "RBLX Operator",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.removeMenu();
  win.loadFile(path.join(__dirname, "renderer", "index.html"));
}

/* ------------------------------------------------------------------ */
/* IPC                                                                 */
/* ------------------------------------------------------------------ */

ipcMain.handle("app:info", () => {
  const root = repoRoot();
  return {
    root,
    packaged: isPackaged(),
    node: "bundled",
    rojo: (() => {
      try {
        const r = spawnSync("rojo", ["--version"], { timeout: 5000, windowsHide: true });
        return !!r && r.status === 0;
      } catch (_) {
        return false;
      }
    })(),
  };
});

ipcMain.handle("operator:run", (_, args) => runPipeline(Array.isArray(args) ? args : []));

ipcMain.handle("operator:abort", () => {
  if (child) child.kill();
  return true;
});

ipcMain.handle("dialog:openSpec", async () => {
  const res = await dialog.showOpenDialog(win, {
    title: "Import a GameSpec designed in any AI chat",
    properties: ["openFile"],
    filters: [
      { name: "GameSpec JSON", extensions: ["json"] },
      { name: "All files", extensions: ["*"] },
    ],
  });
  return res.canceled ? null : res.filePaths[0];
});

ipcMain.handle("settings:get", () => {
  const env = parseEnv(path.join(repoRoot(), ".env"));
  return {
    exists: fs.existsSync(path.join(repoRoot(), ".env")),
    deepseek: env.DEEPSEEK_API_KEY || "",
    meshy: env.MESHY_API_KEY || "",
    openCloud: env.OPEN_CLOUD_API_KEY || "",
    opencodeModel: env.OPENCODE_MODEL || "",
    opencodeAgent: env.OPENCODE_AGENT || "",
  };
});

ipcMain.handle("settings:save", (_, s = {}) => {
  updateEnvFile(path.join(repoRoot(), ".env"), {
    DEEPSEEK_API_KEY: s.deepseek || "",
    MESHY_API_KEY: s.meshy || "",
    OPEN_CLOUD_API_KEY: s.openCloud || "",
    OPENCODE_MODEL: s.opencodeModel || "",
    OPENCODE_AGENT: s.opencodeAgent || "",
  });
  return true;
});

ipcMain.handle("env:open", async () => {
  const envPath = path.join(repoRoot(), ".env");
  if (!fs.existsSync(envPath)) fs.copyFileSync(path.join(repoRoot(), ".env.example"), envPath);
  await shell.openPath(envPath);
  return true;
});

ipcMain.handle("github:status", () => {
  try {
    const r = spawnSync("gh", ["auth", "status"], { encoding: "utf8", timeout: 8000, windowsHide: true });
    if (!r || r.error) return { installed: false, authed: false, output: "" };
    return { installed: true, authed: r.status === 0, output: (r.stdout + r.stderr).slice(0, 400) };
  } catch (_) {
    return { installed: false, authed: false, output: "" };
  }
});

ipcMain.handle("github:link", async () => {
  emit("\n$ gh auth login --hostname github.com --git-protocol https --web\n", "cmd");
  const res = await runChild("gh", ["auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web"]);
  if (res.ok) emit("\n[github] Account linked. You can now create the repo & push.\n", "out");
  else emit("\n[github] Login did not complete. Copy the one-time code from above, log in at the opened\n         page, then use the 'Create repo & push' button. If gh itself is missing, install it\n         once from a terminal:  winget install GitHub.cli  then  gh auth login\n", "err");
  return res;
});

ipcMain.handle("push:run", async (_, opts = {}) => {
  const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    path.join(repoRoot(), "scripts", "push.ps1"), "-Auto", "-SkipVerify"];
  if (opts.repoName) args.push("-RepoName", opts.repoName);
  if (opts.private) args.push("-Private");
  emit(`\n$ powershell -File scripts/push.ps1 -Auto -SkipVerify ${opts.repoName ? `-RepoName ${opts.repoName} ` : ""}${opts.private ? "-Private" : ""}\n`, "cmd");
  return runChild("powershell", args);
});

ipcMain.handle("studio:open", async () => {
  emit("\n$ rojo build default.project.json -o RBLXOperator.rbxl\n", "cmd");
  const res = await runChild("rojo", ["build", "default.project.json", "-o", "RBLXOperator.rbxl"]);
  if (res.error && res.error.includes("ENOENT")) {
    emit("\n[studio] Rojo is not installed. Install it once:\n         run scripts\\studio.ps1 (installs via Rokit), or see https://rojo.space\n", "err");
    return { ok: false, error: res.error };
  }
  if (!res.ok) {
    emit("\n[studio] Build failed — see the errors above.\n", "err");
    return { ok: false, code: res.code };
  }
  const rbxl = path.join(repoRoot(), "RBLXOperator.rbxl");
  await shell.openPath(rbxl);
  emit("\n[studio] Built + opened RBLXOperator.rbxl in Roblox Studio. Press Play.\n", "out");
  return { ok: true };
});

ipcMain.handle("projects:list", () => {
  const dir = path.join(repoRoot(), "games");
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => {
      const spec = path.join(dir, d.name, "spec.json");
      return { name: d.name, hasSpec: fs.existsSync(spec), specPath: spec };
    })
    .filter((p) => p.hasSpec);
});

/* ------------------------------------------------------------------ */

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

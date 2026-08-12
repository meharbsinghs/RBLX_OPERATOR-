"use strict";

/* eslint-disable no-undef */
const $ = (id) => document.getElementById(id);
const op = window.operator;

const consoleEl = $("console");
let lineBuffer = "";
let busy = false;

/* ---------------- console ---------------- */

function log(text, cls) {
  const div = document.createElement("div");
  if (cls) div.className = "line " + cls;
  div.textContent = text;
  consoleEl.appendChild(div);
  consoleEl.scrollTop = consoleEl.scrollHeight;
}

function classify(line) {
  const lower = line.toLowerCase();
  if (/pass|done|pushed|ok\.|complete|success|installed|linked|pushed to/i.test(lower)) return "ok";
  if (/fail|error|abort|not found|denied|refused|failed|✗|econnrefused|enoent/i.test(lower)) return "err";
  if (/warn|note|skip|yellow|not available/i.test(lower)) return "warn";
  return "";
}

function onOutput({ stream, text }) {
  lineBuffer += text;
  const lines = lineBuffer.split("\n");
  lineBuffer = lines.pop();
  for (const line of lines) {
    if (!line.trim()) continue;
    let cls = stream === "err" ? "err" : classify(line);
    log(line, cls);
  }
}

function flushBuffer() {
  if (lineBuffer.trim()) {
    log(lineBuffer, "muted");
    lineBuffer = "";
  }
}

function setBusy(on) {
  busy = on;
  if (!on) flushBuffer(); // a run just ended — emit any trailing partial line
  $("run-state").textContent = on ? "working…" : "idle";
  $("run-state").className = on ? "busy" : "idle";
  for (const b of document.querySelectorAll("button.action")) b.disabled = on;
}

async function runPipeline(args, label) {
  if (busy) { log("[operator] Another task is already running.", "warn"); return null; }
  setBusy(true);
  const res = await op.run(args);
  if (res && res.ok === false && res.error) log(`[${label}] ${res.error}`, "err");
  else log(`[${label}] finished (exit ${res ? res.code : "?"}).`, res && res.ok ? "ok" : "err");
  setBusy(false);
  return res;
}

/* ---------------- tabs ---------------- */

document.querySelectorAll(".tab").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab").forEach((b) => b.classList.remove("active"));
    document.querySelectorAll(".panel").forEach((p) => p.classList.remove("active"));
    btn.classList.add("active");
    $(`tab-${btn.dataset.tab}`).classList.add("active");
    if (btn.dataset.tab === "projects") refreshProjects();
    if (btn.dataset.tab === "publish") refreshGitHub();
  });
});

/* ---------------- design ---------------- */

$("btn-generate").addEventListener("click", async () => {
  const idea = $("idea").value.trim();
  const mode = $("mode").value;
  if (mode === "spec") {
    const file = await op.openSpec();
    if (!file) { log("[design] No spec file selected.", "warn"); return; }
    return runPipeline(["newgame", "--spec", file], "design");
  }
  if (!idea) { log("[design] Describe a game first.", "warn"); return; }
  if (mode === "design") return runPipeline(["design", idea], "design");
  if (mode === "deepseek") return runPipeline(["newgame", idea], "newgame");
  return runPipeline(["newgame", "--offline", idea], "newgame");
});

$("btn-prompt").addEventListener("click", () => runPipeline(["prompt"], "prompt"));
$("btn-env").addEventListener("click", () => op.openEnv());

/* ---------------- verify ---------------- */

$("btn-verify").addEventListener("click", () => runPipeline(["verify"], "verify"));
$("btn-smoke").addEventListener("click", () => runPipeline(["smoke"], "smoke"));
$("btn-studio").addEventListener("click", async () => {
  if (busy) { log("[studio] Another task is already running.", "warn"); return; }
  setBusy(true);
  const res = await op.openStudio();
  if (res && res.ok === false) log(`[studio] ${res.error || "build failed — see output above."}`, "err");
  setBusy(false);
});

/* ---------------- publish ---------------- */

async function refreshGitHub() {
  const st = await op.githubStatus();
  const chip = $("chip-gh");
  const note = $("gh-status");
  if (!st.installed) {
    chip.textContent = "GitHub: gh not installed";
    chip.className = "chip warn";
    note.textContent = "GitHub CLI (gh) is not installed.\nUse the 'Link GitHub account' button — it installs nothing itself,\nbut push.ps1 will install gh via winget automatically when you push.\nOr install once:  winget install GitHub.cli  then  gh auth login";
    return;
  }
  if (st.authed) {
    chip.textContent = "GitHub: linked ✓";
    chip.className = "chip ok";
    note.textContent = st.output.trim() || "Authenticated.";
  } else {
    chip.textContent = "GitHub: not linked";
    chip.className = "chip bad";
    note.textContent = "Not linked yet. Click 'Link GitHub account' — a browser opens with a\none-time code; log in and paste the code back.";
  }
}

$("btn-link").addEventListener("click", async () => {
  if (busy) { log("[github] Another task is already running.", "warn"); return; }
  setBusy(true);
  const res = await op.linkGitHub();
  setBusy(false);
  refreshGitHub();
  if (res && res.ok) log("[github] Account linked.", "ok");
});

$("btn-push").addEventListener("click", async () => {
  if (busy) { log("[push] Another task is already running.", "warn"); return; }
  log("$ node pipeline/bridge.js verify  (gate before push)", "cmd");
  setBusy(true);
  const v = await op.run(["verify"]);
  if (!v || !v.ok) {
    log("[push] Verify gate FAILED — fix the issues above before pushing.", "err");
    setBusy(false);
    return;
  }
  log("[push] Verify gate passed.", "ok");
  const res = await op.push({
    repoName: $("repo-name").value.trim() || "RBLX_OPERATOR-",
    private: $("repo-private").checked,
  });
  setBusy(false);
  if (res && res.ok) {
    log("[push] Pushed to GitHub. CI will validate the engine automatically.", "ok");
    refreshGitHub();
  }
});

/* ---------------- projects ---------------- */

async function refreshProjects() {
  const list = $("project-list");
  const items = await op.listProjects();
  if (!items.length) {
    list.innerHTML = '<span class="hint">No designs yet — go to the Design tab and generate one.</span>';
    return;
  }
  list.innerHTML = "";
  for (const p of items) {
    const row = document.createElement("div");
    row.className = "project-row";
    const info = document.createElement("div");
    const name = document.createElement("div");
    name.className = "pname";
    name.textContent = p.name;
    const spec = document.createElement("div");
    spec.className = "pspec";
    spec.textContent = p.specPath;
    info.append(name, spec);
    const btn = document.createElement("button");
    btn.textContent = "Recompile";
    btn.classList.add("secondary", "action");
    btn.addEventListener("click", () => runPipeline(["newgame", "--spec", p.specPath], "recompile"));
    row.append(info, btn);
    list.appendChild(row);
  }
}

/* ---------------- settings ---------------- */

async function loadSettings() {
  const s = await op.getSettings();
  $("set-deepseek").value = s.deepseek || "";
  $("set-meshy").value = s.meshy || "";
  $("set-opencloud").value = s.openCloud || "";
  $("set-opencode-model").value = s.opencodeModel || "";
  $("set-opencode-agent").value = s.opencodeAgent || "";
}

$("btn-save-settings").addEventListener("click", async () => {
  await op.saveSettings({
    deepseek: $("set-deepseek").value.trim(),
    meshy: $("set-meshy").value.trim(),
    openCloud: $("set-opencloud").value.trim(),
    opencodeModel: $("set-opencode-model").value.trim(),
    opencodeAgent: $("set-opencode-agent").value.trim(),
  });
  log("[settings] Saved to .env (gitignored — never committed).", "ok");
});

$("btn-env2").addEventListener("click", () => op.openEnv());
$("btn-clear").addEventListener("click", () => { consoleEl.innerHTML = ""; });
$("btn-abort").addEventListener("click", () => op.abort());

/* ---------------- boot ---------------- */

op.onOutput(onOutput);
setBusy(false);
loadSettings();
refreshGitHub();

op.info().then((info) => {
  $("root-path").textContent = `engine: ${info.root}`;
  $("root-path").title = info.root;
  $("chip-node").textContent = "Node: bundled ✓";
  $("chip-node").className = "chip ok";
  $("chip-rojo").textContent = info.rojo ? "Rojo: found ✓" : "Rojo: not installed";
  $("chip-rojo").className = info.rojo ? "chip ok" : "chip warn";
  log(`RBLX Operator Studio ready. Engine at ${info.root}${info.packaged ? " (per-user workspace)" : ""}.`, "muted");
  log('Tip: describe a game in the Design tab and press Generate Game.', "muted");
});

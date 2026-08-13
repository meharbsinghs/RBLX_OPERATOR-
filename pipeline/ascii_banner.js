"use strict";

/**
 * RBLX Operator — Unicode block banner.
 *
 * Renders the BUILDER BOI mascot (assets/branding/logo.png) as crisp Unicode
 * block art — half-block vertical resolution (█ ▀ ▄), the same blocky style
 * opencode uses for its terminal logo. Zero dependencies: hand-rolled PNG
 * decoder + box-sampled alpha/luminance mapping.
 *
 *   node pipeline/ascii_banner.js               # print to stdout
 *   node pipeline/ascii_banner.js --save path   # write plain text file
 *   node pipeline/ascii_banner.js --cols 80     # target width (any size, 40-110)
 *   node pipeline/ascii_banner.js --color       # ANSI 256: gray body, logo-orange eyes
 */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.join(__dirname, "..");

/* ------------------------------------------------------------------ *
 * Tiny PNG decoder (8-bit, non-interlaced; RGB/RGBA/gray/palette)
 * ------------------------------------------------------------------ */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let width = 0,
    height = 0,
    bitDepth = 0,
    colorType = 0,
    interlace = 0;
  const idat = [];
  let palette = null;
  let pos = 8;
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.slice(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data.readUInt8(8);
      colorType = data.readUInt8(9);
      interlace = data.readUInt8(12);
    } else if (type === "PLTE") {
      palette = data;
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + len;
  }
  if (!width || !height || bitDepth !== 8) throw new Error("unsupported PNG (need 8-bit)");
  if (interlace !== 0) throw new Error("interlaced PNG not supported");
  if (colorType === 3 && !palette) throw new Error("palette PNG without PLTE");

  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : colorType === 3 ? 1 : 1;
  const stride = width * channels;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const out = Buffer.alloc(width * height * 4);

  const paeth = (a, b, c) => {
    const p = a + b - c;
    const pa = Math.abs(p - a),
      pb = Math.abs(p - b),
      pc = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
  };

  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = Buffer.from(line);
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0;
      const b = prev[x];
      const c = x >= channels ? prev[x - channels] : 0;
      if (filter === 1) cur[x] = (cur[x] + a) & 0xff;
      else if (filter === 2) cur[x] = (cur[x] + b) & 0xff;
      else if (filter === 3) cur[x] = (cur[x] + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) cur[x] = (cur[x] + paeth(a, b, c)) & 0xff;
    }
    for (let x = 0; x < width; x++) {
      const si = x * channels;
      const di = (y * width + x) * 4;
      if (colorType === 6) {
        out[di] = cur[si];
        out[di + 1] = cur[si + 1];
        out[di + 2] = cur[si + 2];
        out[di + 3] = cur[si + 3];
      } else if (colorType === 2) {
        out[di] = cur[si];
        out[di + 1] = cur[si + 1];
        out[di + 2] = cur[si + 2];
        out[di + 3] = 255;
      } else if (colorType === 3) {
        const pi = cur[si] * 3;
        out[di] = palette[pi];
        out[di + 1] = palette[pi + 1];
        out[di + 2] = palette[pi + 2];
        out[di + 3] = 255;
      } else {
        out[di] = cur[si];
        out[di + 1] = cur[si];
        out[di + 2] = cur[si];
        out[di + 3] = 255;
      }
    }
    prev = cur;
  }
  return { width, height, data: out };
}

/* ------------------------------------------------------------------ *
 * Unicode half-block renderer.
 *
 * Each terminal cell covers 2 source pixel rows: if the top half is filled
 * and the bottom is not, print ▀ (upper half block); vice-versa ▄; both █;
 * neither a space. That gives 2x vertical resolution and crisp edges.
 * ------------------------------------------------------------------ */

const ALPHA_CUT = 60; // below this alpha the pixel is transparent

function lum(r, g, b) {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

// Estimate the image's background luminance from its border ring, so the
// fill threshold adapts to light-on-dark, dark-on-light, and transparent
// logos alike.
function estimateBgLum(data, width, height) {
  let s = 0,
    n = 0;
  const ring = (x, y) => {
    const i = (y * width + x) * 4;
    s += lum(data[i], data[i + 1], data[i + 2]);
    n++;
  };
  const step = Math.max(1, Math.floor(width / 120));
  for (let x = 0; x < width; x += step) {
    ring(x, 0);
    ring(x, height - 1);
  }
  for (let y = step; y < height - 1; y += step) {
    ring(0, y);
    ring(width - 1, y);
  }
  return n ? s / n : 0;
}

function avgRegion(data, width, x0, x1, y0, y1) {
  let r = 0,
    g = 0,
    b = 0,
    a = 0,
    n = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * width + x) * 4;
      r += data[i];
      g += data[i + 1];
      b += data[i + 2];
      a += data[i + 3];
      n++;
    }
  }
  return { r: r / n, g: g / n, b: b / n, a: a / n };
}

const esc = (code, s) => `\x1b[38;5;${code}m${s}\x1b[0m`;

// One accent only, matched to the logo's palette: 214 = the logo's orange
// (#f8a808 -> ANSI 214), 246 = the logo's neutral gray (#989898 -> ANSI 246).
// Eyes/visor get the orange; the body stays gray. Nothing else gets color.
const ACCENT = "214";
const BODY = "246";

function renderBlockLogo(pngPath, cols) {
  const { width, height, data } = decodePng(fs.readFileSync(pngPath));
  const bgLum = estimateBgLum(data, width, height);
  const fillCut = bgLum + 14; // must beat the background by a clear margin
  const pxPerCell = width / cols;
  const rows = Math.max(4, Math.round(height / (2 * pxPerCell)));
  const lines = [];
  for (let oy = 0; oy < rows; oy++) {
    let line = "";
    for (let ox = 0; ox < cols; ox++) {
      const x0 = Math.floor(ox * pxPerCell);
      const x1 = Math.max(x0 + 1, Math.floor((ox + 1) * pxPerCell));
      const yTop = Math.floor(oy * 2 * pxPerCell);
      const yMid = Math.floor((oy * 2 + 1) * pxPerCell);
      const yBot = Math.max(yMid + 1, Math.floor((oy * 2 + 2) * pxPerCell));
      const top = avgRegion(data, width, x0, x1, yTop, yMid);
      const bot = avgRegion(data, width, x0, x1, yMid, yBot);
      const tFill = top.a > ALPHA_CUT && lum(top.r, top.g, top.b) > fillCut;
      const bFill = bot.a > ALPHA_CUT && lum(bot.r, bot.g, bot.b) > fillCut;
      let ch = " ";
      if (tFill && bFill) ch = "█";
      else if (tFill) ch = "▀";
      else if (bFill) ch = "▄";
      line += ch;
    }
    lines.push(line.replace(/\s+$/, ""));
  }
  return lines.join("\n").replace(/^\s*$\n/gm, "").trimEnd();
}

// Find the visor/eye rows of the rendered BOI art: lines in the upper portion
// whose glyphs are split by a wide empty run (the eye slits). The accent lands
// only there — the body stays neutral gray.
function findEyeRows(lines) {
  const rows = [];
  const cap = Math.max(3, Math.floor(lines.length * 0.45));
  for (let i = 0; i < Math.min(lines.length, cap); i++) {
    const first = lines[i].search(/\S/);
    if (first === -1) continue;
    const last = lines[i].search(/\S\s*$/);
    let run = 0,
      best = 0;
    for (const ch of lines[i].slice(first, last + 1)) {
      if (ch === " ") {
        run++;
        best = Math.max(best, run);
      } else {
        run = 0;
      }
    }
    if (best >= 8) rows.push(i);
  }
  return rows;
}

// Apply ANSI color to already-rendered plain art. The characters never change
// — only color: body neutral gray, the eye rows phosphor green.
function colorizeLines(art, eyeRows) {
  const eye = new Set(eyeRows);
  return art
    .split("\n")
    .map((line, i) => {
      if (!/[█▀▄]/.test(line)) return line;
      return line.replace(/[█▀▄]/g, (m) => esc(eye.has(i) ? ACCENT : BODY, m));
    })
    .join("\n");
}

/* ------------------------------------------------------------------ *
 * Blocky wordmark — 5x7 font in opencode's style.
 * ------------------------------------------------------------------ */
const FONT = {
  A: ["███", "█ █", "███", "█ █", "█ █"],
  B: ["██ ", "█ █", "██ ", "█ █", "██ "],
  C: [" ██", "█  ", "█  ", "█  ", " ██"],
  D: ["██ ", "█ █", "█ █", "█ █", "██ "],
  E: ["███", "█  ", "██ ", "█  ", "███"],
  F: ["███", "█  ", "██ ", "█  ", "█  "],
  G: [" ██", "█  ", "█ █", "█ █", " ██"],
  H: ["█ █", "█ █", "███", "█ █", "█ █"],
  I: ["███", " █ ", " █ ", " █ ", "███"],
  J: ["  █", "  █", "  █", "█ █", " █ "],
  K: ["█ █", "█ █", "██ ", "█ █", "█ █"],
  L: ["█  ", "█  ", "█  ", "█  ", "███"],
  M: ["█ █", "███", "█ █", "█ █", "█ █"],
  N: ["█ █", "███", "█ █", "█ █", "█ █"],
  O: [" █ ", "█ █", "█ █", "█ █", " █ "],
  P: ["██ ", "█ █", "██ ", "█  ", "█  "],
  Q: [" █ ", "█ █", "█ █", "█ █", " ██"],
  R: ["██ ", "█ █", "██ ", "█ █", "█ █"],
  S: [" ██", "█  ", " █ ", "  █", "██ "],
  T: ["███", " █ ", " █ ", " █ ", " █ "],
  U: ["█ █", "█ █", "█ █", "█ █", "███"],
  V: ["█ █", "█ █", "█ █", "█ █", " █ "],
  W: ["█ █", "█ █", "█ █", "███", "█ █"],
  X: ["█ █", "█ █", " █ ", "█ █", "█ █"],
  Y: ["█ █", "█ █", " █ ", " █ ", " █ "],
  Z: ["███", "  █", " █ ", "█  ", "███"],
  " ": ["   ", "   ", "   ", "   ", "   "],
  ".": ["   ", "   ", "   ", "   ", "██ "],
  "-": ["   ", "   ", "███", "   ", "   "],
  "_": ["   ", "   ", "   ", "   ", "███"],
  "0": [" █ ", "█ █", "█ █", "█ █", " █ "],
  "1": [" █ ", "██ ", " █ ", " █ ", "███"],
  "2": [" ██", "  █", " █ ", "█  ", "███"],
  "3": ["██ ", "  █", " █ ", "  █", "██ "],
  "4": ["█ █", "█ █", "███", "  █", "  █"],
  "5": ["███", "█  ", "██ ", "  █", "██ "],
  "6": [" ██", "█  ", "███", "█ █", "███"],
  "7": ["███", "  █", " █ ", " █ ", " █ "],
  "8": [" █ ", "█ █", " █ ", "█ █", " █ "],
  "9": ["███", "█ █", "███", "  █", "██ "],
};

function wordmark(text, pad = 2) {
  const letters = text.toUpperCase().split("");
  const rows = [];
  for (let row = 0; row < 5; row++) {
    rows.push(letters.map((ch) => (FONT[ch] || FONT[" "])[row]).join(" ".repeat(pad)));
  }
  return rows.join("\n");
}

function banner(opts = {}) {
  const cols = opts.cols || 56;  // 56-col default: smaller, always fits a console
  const color = !!opts.color;
  const logoPath = opts.logoPath || path.join(ROOT, "assets", "branding", "logo.png");
  let art = "";
  try {
    art = renderBlockLogo(logoPath, cols);
  } catch (err) {
    // Fallback: blocky wordmark mascot when the PNG is unavailable.
    art = wordmark("RBLX OPERATOR", 3);
  }
  if (color) art = colorizeLines(art, findEyeRows(art.split("\n")));
  return [
    art,
    "",
    wordmark("RBLX OPERATOR", 2),
    "",
    "  one prompt -> one complete, playable Roblox game",
    "  orchestrated by opencode  ·  the prompt decides the genre  ·  free & open source",
    "",
  ].join("\n");
}

// Apply ANSI color to block chars in already-rendered plain text — all in the
// accent, for cases that want a single flat color (e.g. the wordmark).
function colorizeBlocks(text, { hot = ACCENT } = {}) {
  return text.replace(/[█▀▄]/g, (m) => esc(hot, m));
}

function main() {
  const args = process.argv.slice(2);
  let cols = 56;
  let save = null;
  let color = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--cols") cols = parseInt(args[++i], 10) || 56;
    else if (args[i] === "--save") save = args[++i];
    else if (args[i] === "--color") color = true;
  }
  const text = banner({ cols, color });
  if (save) {
    // Always write the plain (uncolored) art to the saved file.
    const plain = banner({ cols });
    fs.mkdirSync(path.dirname(save), { recursive: true });
    fs.writeFileSync(save, plain + "\n");
    console.log(`[ascii] wrote ${save} (${plain.split("\n").length} lines, ${cols} cols)`);
  } else {
    console.log(text);
  }
}

if (require.main === module) main();

module.exports = { banner, renderBlockLogo, wordmark, colorizeBlocks, findEyeRows };

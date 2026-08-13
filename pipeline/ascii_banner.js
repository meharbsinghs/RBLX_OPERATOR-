"use strict";

/**
 * RBLX Operator — ASCII banner.
 *
 * Renders the BUILDER BOI mascot (assets/branding/logo.png) to ASCII art with
 * zero dependencies (hand-rolled PNG decoder + box-sampled luminance mapping),
 * plus a blocky "RBLX OPERATOR" wordmark in the style of opencode's own logo.
 *
 *   node pipeline/ascii_banner.js              # print to stdout
 *   node pipeline/ascii_banner.js --save path  # write plain text file
 *   node pipeline/ascii_banner.js --cols 80    # target width
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
    colorType = 0;
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
  if (data[12] !== 0) throw new Error("interlaced PNG not supported");
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
 * Rendering
 * ------------------------------------------------------------------ */
// dark -> light ramp. Warm, suited to the cream-on-black aesthetic.
const RAMP = "  .·:+*xX$&#@%";
const BG_LUM = 0.066; // #131010

function lum(r, g, b) {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function isOrange(r, g, b) {
  return r > 120 && g > 40 && g < 170 && b < 110 && r > g + 40 && g > b;
}

function renderLogo(pngPath, cols) {
  const { width, height, data } = decodePng(fs.readFileSync(pngPath));
  const rows = Math.max(4, Math.round((cols * height) / width / 2.1));
  const lines = [];
  for (let oy = 0; oy < rows; oy++) {
    let line = "";
    for (let ox = 0; ox < cols; ox++) {
      const x0 = Math.floor((ox * width) / cols);
      const x1 = Math.max(x0 + 1, Math.floor(((ox + 1) * width) / cols));
      const y0 = Math.floor((oy * height) / rows);
      const y1 = Math.max(y0 + 1, Math.floor(((oy + 1) * height) / rows));
      let r = 0,
        g = 0,
        b = 0,
        alpha = 0,
        n = 0;
      for (let y = y0; y < y1; y++) {
        for (let x = x0; x < x1; x++) {
          const i = (y * width + x) * 4;
          r += data[i];
          g += data[i + 1];
          b += data[i + 2];
          alpha += data[i + 3];
          n++;
        }
      }
      r /= n;
      g /= n;
      b /= n;
      alpha /= n;
      const l = alpha < 40 ? BG_LUM : lum(r, g, b) / 255;
      const idx = Math.min(RAMP.length - 1, Math.max(0, Math.round(l * (RAMP.length - 1))));
      line += RAMP[idx];
    }
    lines.push(line.replace(/\s+$/, ""));
  }
  return lines.join("\n").replace(/^\s*$\n/gm, "").trimEnd();
}

/* Blocky wordmark — 5x7 font in opencode's style. */
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
  const cols = opts.cols || 84;
  const logoPath = opts.logoPath || path.join(ROOT, "assets", "branding", "logo.png");
  let art = "";
  try {
    art = renderLogo(logoPath, cols);
  } catch (err) {
    // Fallback: blocky wordmark mascot when the PNG is unavailable.
    art = wordmark("RBLX OPERATOR", 3);
  }
  return [
    art,
    "",
    wordmark("RBLX OPERATOR", 2),
    "",
    "  one prompt -> one complete, playable Roblox game",
    "  orchestrated by opencode  ·  ships games  ·  free & open source",
    "",
  ].join("\n");
}

function main() {
  const args = process.argv.slice(2);
  let cols = 84;
  let save = null;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--cols") cols = parseInt(args[++i], 10) || 84;
    else if (args[i] === "--save") save = args[++i];
  }
  const text = banner({ cols });
  if (save) {
    fs.mkdirSync(path.dirname(save), { recursive: true });
    fs.writeFileSync(save, text + "\n");
    console.log(`[ascii] wrote ${save} (${text.split("\n").length} lines)`);
  } else {
    console.log(text);
  }
}

if (require.main === module) main();

module.exports = { banner, renderLogo, wordmark };

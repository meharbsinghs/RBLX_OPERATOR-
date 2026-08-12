"use strict";

/**
 * build_icon.js — zero-dependency PNG -> ICO pipeline (pure Node, no npm).
 *
 * Reads assets/branding/logo.png (the committed RBLX Operator mark) and writes:
 *   assets/branding/icon.ico     16/32/48/128/256 multi-size Windows icon
 *   assets/branding/logo-256.png 256px square PNG for the site + desktop app
 *
 * CI runs this before packaging (see .github/workflows/build-exe.yml and
 * deploy-site.yml), so the .exe and the website always ship the current logo.
 * Swap assets/branding/logo.png for a new mark and rebuild — no other changes.
 */

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const BRANDING = path.join(__dirname, "..", "assets", "branding");
const SRC = path.join(BRANDING, "logo.png");

/* ------------------------------------------------------------------ */
/* PNG decode (8-bit gray / gray+alpha / RGB / RGBA, non-interlaced)   */
/* ------------------------------------------------------------------ */

function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG file");
  let pos = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("latin1", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error("interlaced PNG not supported");
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + len;
  }
  if (bitDepth !== 8) throw new Error(`bit depth ${bitDepth} not supported (need 8)`);
  const bpp = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  if (!bpp) throw new Error(`color type ${colorType} not supported`);

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * bpp;
  const out = Buffer.alloc(width * height * 4);
  const prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? line[x - bpp] : 0;
      const b = y > 0 ? prev[x] : 0;
      const c = x >= bpp && y > 0 ? prev[x - bpp] : 0;
      if (filter === 1) line[x] = (line[x] + a) & 0xff;
      else if (filter === 2) line[x] = (line[x] + b) & 0xff;
      else if (filter === 3) line[x] = (line[x] + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        line[x] = (line[x] + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xff;
      }
    }
    for (let x = 0; x < stride; x++) prev[x] = line[x];
    for (let x = 0; x < width; x++) {
      const si = x * bpp;
      const di = (y * width + x) * 4;
      out[di] = line[si];
      if (bpp === 1) {
        out[di + 1] = out[di];
        out[di + 2] = out[di];
        out[di + 3] = 255;
      } else if (bpp === 2) {
        out[di + 1] = line[si];
        out[di + 2] = line[si];
        out[di + 3] = line[si + 1];
      } else if (bpp === 3) {
        out[di + 1] = line[si + 1];
        out[di + 2] = line[si + 2];
        out[di + 3] = 255;
      } else {
        out[di + 1] = line[si + 1];
        out[di + 2] = line[si + 2];
        out[di + 3] = line[si + 3];
      }
    }
  }
  return { width, height, pixels: out };
}

/* ------------------------------------------------------------------ */
/* Box-sampled downscale                                               */
/* ------------------------------------------------------------------ */

function resize(pixels, srcW, srcH, dstW, dstH) {
  const out = Buffer.alloc(dstW * dstH * 4);
  const xr = srcW / dstW;
  const yr = srcH / dstH;
  for (let y = 0; y < dstH; y++) {
    const ys = Math.floor(y * yr);
    const ye = Math.min(srcH, Math.ceil((y + 1) * yr));
    for (let x = 0; x < dstW; x++) {
      const xs = Math.floor(x * xr);
      const xe = Math.min(srcW, Math.ceil((x + 1) * xr));
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = ys; sy < ye; sy++) {
        for (let sx = xs; sx < xe; sx++) {
          const i = (sy * srcW + sx) * 4;
          r += pixels[i];
          g += pixels[i + 1];
          b += pixels[i + 2];
          a += pixels[i + 3];
          n += 1;
        }
      }
      const i = (y * dstW + x) * 4;
      out[i] = Math.round(r / n);
      out[i + 1] = Math.round(g / n);
      out[i + 2] = Math.round(b / n);
      out[i + 3] = Math.round(a / n);
    }
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* PNG encode (8-bit RGBA, filter 0)                                   */
/* ------------------------------------------------------------------ */

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "latin1");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

function encodePng(width, height, pixels) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    pixels.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/* ------------------------------------------------------------------ */
/* ICO container (PNG-compressed entries)                              */
/* ------------------------------------------------------------------ */

function encodeIco(entries) {
  const count = entries.length;
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(count, 4);
  const parts = [header];
  let offset = 6 + count * 16;
  for (const e of entries) {
    const dir = Buffer.alloc(16);
    dir[0] = e.size >= 256 ? 0 : e.size;
    dir[1] = e.size >= 256 ? 0 : e.size;
    dir[2] = 0;
    dir[3] = 0;
    dir.writeUInt16LE(1, 4); // planes
    dir.writeUInt16LE(32, 6); // bit count
    dir.writeUInt32LE(e.png.length, 8);
    dir.writeUInt32LE(offset, 12);
    parts.push(dir);
    offset += e.png.length;
  }
  for (const e of entries) parts.push(e.png);
  return Buffer.concat(parts);
}

/* ------------------------------------------------------------------ */

function main() {
  if (!fs.existsSync(SRC)) {
    console.error(`[build-icon] missing ${SRC} — copy the RBLX Operator logo there first.`);
    process.exit(1);
  }
  const src = fs.readFileSync(SRC);
  const img = decodePng(src);
  console.log(`[build-icon] decoded ${img.width}x${img.height} logo`);

  const sizes = [256, 128, 48, 32, 16];
  const entries = [];
  for (const size of sizes) {
    const pixels = size === img.width ? img.pixels : resize(img.pixels, img.width, img.height, size, size);
    const png = encodePng(size, size, pixels);
    entries.push({ size, png });
    if (size === 256) {
      fs.writeFileSync(path.join(BRANDING, "logo-256.png"), png);
    }
  }
  fs.writeFileSync(path.join(BRANDING, "icon.ico"), encodeIco(entries));
  console.log(`[build-icon] wrote assets/branding/icon.ico (${sizes.join("/")}) + logo-256.png`);
}

main();

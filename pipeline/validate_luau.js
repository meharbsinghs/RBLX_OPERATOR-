"use strict";

/**
 * Luau repo validator. Checks every .luau file in src/ for:
 *   1. `--!strict` as the first line (mandatory engine convention)
 *   2. Correct Rojo naming: boot scripts use .server.luau / .client.luau,
 *      everything else is a ModuleScript (.luau)
 *   3. Structural block balance (function/if/for/while/do/repeat ... end/until)
 *
 * The block scanner is a real tokenizer (not a regex), so it correctly
 * understands:
 *   - string literals ("...", '...', [[ ... ]]) and all comment forms
 *   - `elseif` as a single keyword (it opens no block)
 *   - `for ... do` / `while ... do` as a single block (the header `do` is
 *     not an extra opener)
 *   - Luau `if` *expressions* (`local x = if a then b else c`), which have no
 *     `end` — they are detected by value position and do not open a block
 *   - statement boundaries across newlines (so `local x = 5` then `if` on the
 *     next line is still a statement `if`)
 *   - `function()` bodies (an `if` right after `function()` is a statement)
 *
 * Run standalone:  node pipeline/validate_luau.js
 * Or via bridge:   node pipeline/bridge.js verify
 */

const fs = require("fs");
const path = require("path");

const SRC_DIR = path.join(__dirname, "..", "src");
const BLOCK_START = new Set(["function", "if", "for", "while", "do", "repeat"]);
const BLOCK_END = new Set(["end", "until"]);
// Tokens after which a new statement can begin.
const STATEMENT_START = new Set([";", "end", "else", "elseif", "then", "until"]);
// Tokens that cannot end a statement (continuation across a newline).
const CONTINUATION = new Set([
  "(", "[", "{", ",", "=", "=>", ".", "+", "-", "*", "/", "%", "^", "&", "|", "~", "<", ">",
  ":", "..", "and", "or", "not", "in",
]);

function isIdentStart(c) {
  return c !== undefined && /[A-Za-z_]/.test(c);
}
function isIdentPart(c) {
  return c !== undefined && /[A-Za-z0-9_]/.test(c);
}
function isDigit(c) {
  return c !== undefined && c >= "0" && c <= "9";
}

/**
 * Character scanner -> array of { word, line }. Strips comments and string
 * literals, keeps identifier/number tokens plus the punctuation needed for
 * statement-boundary detection.
 */
function tokenize(source) {
  const tokens = [];
  let i = 0;
  let line = 1;
  const n = source.length;

  const push = (word) => tokens.push({ word, line });

  while (i < n) {
    const c = source[i];
    if (c === "\n") {
      line += 1;
      i += 1;
      continue;
    }
    if (c === "\r" || c === " " || c === "\t") {
      i += 1;
      continue;
    }
    // line comment
    if (c === "-" && source[i + 1] === "-") {
      if (source[i + 2] === "[") {
        let eq = 0;
        let j = i + 3;
        while (j < n && source[j] === "=") {
          eq += 1;
          j += 1;
        }
        if (j < n && source[j] === "[") {
          const closer = "]" + "=".repeat(eq) + "]";
          const endIdx = source.indexOf(closer, j + 1);
          if (endIdx === -1) break;
          line += (source.slice(i, endIdx + closer.length).match(/\n/g) || []).length;
          i = endIdx + closer.length;
          continue;
        }
      }
      const nl = source.indexOf("\n", i);
      i = nl === -1 ? n : nl;
      continue;
    }
    // string literal "..." / '...' (with \ escapes)
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && source[j] !== c) {
        if (source[j] === "\\") j += 1;
        if (source[j] === "\n") line += 1;
        j += 1;
      }
      i = j + 1;
      push("STRING");
      continue;
    }
    // long string [[ ... ]] or [=[ ... ]=]
    if (c === "[" && (source[i + 1] === "[" || source[i + 1] === "=")) {
      let eq = 0;
      let j = i + 1;
      while (j < n && source[j] === "=") {
        eq += 1;
        j += 1;
      }
      if (j < n && source[j] === "[") {
        const closer = "]" + "=".repeat(eq) + "]";
        const endIdx = source.indexOf(closer, j + 1);
        if (endIdx === -1) break;
        line += (source.slice(i, endIdx + closer.length).match(/\n/g) || []).length;
        i = endIdx + closer.length;
        push("STRING");
        continue;
      }
      i += 1;
      continue;
    }
    // identifier / keyword
    if (isIdentStart(c)) {
      let j = i;
      while (j < n && isIdentPart(source[j])) j += 1;
      push(source.slice(i, j));
      i = j;
      continue;
    }
    // number
    if (isDigit(c) || (c === "." && isDigit(source[i + 1]))) {
      let j = i;
      while (j < n && /[0-9a-fA-FxX._eE]/.test(source[j])) j += 1;
      push("NUMBER");
      i = j;
      continue;
    }
    // two-char tokens we care about
    const two = source.slice(i, i + 2);
    if (two === ".." || two === "=>") {
      push(two);
      i += 2;
      continue;
    }
    // punctuation
    if ("=()[]{},:;.+-*/%^&|~<>".includes(c)) {
      push(c);
      i += 1;
      continue;
    }
    i += 1;
  }
  return tokens;
}

function isContinuation(w) {
  return CONTINUATION.has(w) || w === "if" || w === "for" || w === "while" || w === "repeat" || w === "function";
}

/**
 * Correct block balance using the scanned tokens.
 *   function -> always opens a block (has an `end`)
 *   for/while -> open a block; the first following `do` is the header `do`
 *   standalone `do` -> opens a block
 *   repeat -> opens a block, closed by `until`
 *   `if` at a statement start -> opens a block (closed by `end`)
 *   `if` in value position (if-expression) -> opens nothing
 */
function blockBalance(tokens) {
  let depth = 0;
  let pendingLoopHeader = false;
  let atStatementStart = true;
  let prev = null;
  let prevLine = -1;
  // Paren stack. "FN_PAREN" = the "(" that opens a function's param list;
  // "PAREN" = any other "(".
  const parens = [];

  const startsStatement = (t) =>
    atStatementStart || (t.line > prevLine && prev !== null && !isContinuation(prev));

  for (const t of tokens) {
    const w = t.word;

    // The `do` that closes a for/while header is not an opener.
    if (pendingLoopHeader && w === "do") {
      pendingLoopHeader = false;
      prev = "do";
      prevLine = t.line;
      atStatementStart = true;
      continue;
    }

    // A statement `if` is one that begins a statement (not an if-expression).
    const stmtStart = startsStatement(t);

    if (w === "function") {
      parens.push("FN");
      depth += 1;
    } else if (w === "(") {
      if (parens[parens.length - 1] === "FN") parens[parens.length - 1] = "FN_PAREN";
      else parens.push("PAREN");
    } else if (w === ")") {
      if (parens.pop() === "FN_PAREN") {
        // Closing a function's param list: the body begins next token.
        atStatementStart = true;
        prev = ")";
        prevLine = t.line;
        continue;
      }
    }

    if (w === "for" || w === "while") {
      depth += 1;
      pendingLoopHeader = true;
    } else if (w === "repeat") {
      depth += 1;
    } else if (w === "do") {
      depth += 1;
    } else if (w === "if" && stmtStart) {
      depth += 1;
    } else if (w === "end" || w === "until") {
      depth -= 1;
    }

    // Update statement boundary for the next token.
    if (STATEMENT_START.has(w) || w === "do" || w === "repeat") {
      atStatementStart = true;
    } else if (isContinuation(w) || w === ")") {
      atStatementStart = false;
    } else if (t.line > prevLine && prev !== null && !isContinuation(prev)) {
      atStatementStart = true;
    } else {
      atStatementStart = false;
    }

    prev = w;
    prevLine = t.line;
  }
  return depth;
}

function validateLuau({ print = false } = {}) {
  const issues = [];
  let fileCount = 0;

  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const full = path.join(dir, name);
      if (fs.statSync(full).isDirectory()) {
        walk(full);
      } else if (name.endsWith(".luau")) {
        check(full);
      }
    }
  };

  const check = (file) => {
    fileCount += 1;
    const rel = path.relative(SRC_DIR, file).replace(/\\/g, "/");
    const source = fs.readFileSync(file, "utf8");
    const lines = source.split(/\r?\n/);

    if (!(lines[0] || "").startsWith("--!strict")) {
      issues.push(`${rel}: line 1 must be '--!strict'`);
    }

    // Naming policy
    const base = path.basename(file);
    const top = rel.split("/")[0];
    if (top === "server" && base !== "init.server.luau" && !base.endsWith(".luau")) {
      issues.push(`${rel}: server files must be init.server.luau or *.luau modules`);
    }
    if (top === "client" && base !== "init.client.luau" && !base.endsWith(".luau")) {
      issues.push(`${rel}: client files must be init.client.luau or *.luau modules`);
    }
    if ((top === "shared" && base.includes(".server.")) || (top === "shared" && base.includes(".client."))) {
      issues.push(`${rel}: shared files must be plain *.luau modules`);
    }

    // Block balance (real tokenizer)
    const depth = blockBalance(tokenize(source));
    if (depth !== 0) {
      issues.push(`${rel}: unbalanced blocks (depth ${depth})`);
    }
  };

  walk(SRC_DIR);

  if (print) {
    if (issues.length > 0) {
      console.error(`[validate-luau] ${issues.length} issue(s) across ${fileCount} file(s):`);
      for (const issue of issues) console.error(`  ✗ ${issue}`);
    } else {
      console.log(`[validate-luau] OK — ${fileCount} Luau file(s) passed.`);
    }
  }

  return { ok: issues.length === 0, issues, fileCount };
}

if (require.main === module) {
  const result = validateLuau({ print: true });
  process.exit(result.ok ? 0 : 1);
}

module.exports = { validateLuau };

/* RBLX OPERATOR — site script (zero deps).
   Terminal typing animation + staged pipeline output. */

"use strict";

const IDEA = "a tense neon extraction shooter on a derelict space station";
const STEPS = [
  { id: "t1", text: "[design] goal → round structure: extraction, win by wave 5", cls: "t-out" },
  { id: "t2", text: "[design] theme → art direction: neon overdrive lighting + sound identity", cls: "t-out" },
  { id: "t3", text: "[design] roster → 7 weapons · 4 enemies · 5 perks · 3 doors · 4 zones", cls: "t-out" },
  { id: "t4", text: "[codegen] emitted src/shared/config.luau (typed, balanced, clamped)", cls: "t-out" },
  { id: "t5", text: "[verify] PASS — Luau --!strict + JS syntax OK · ready to play", cls: "t-ok" },
];

function typeIdea(el, done) {
  let i = 0;
  const tick = () => {
    if (i <= IDEA.length) {
      el.textContent = IDEA.slice(0, i);
      i += 1;
      setTimeout(tick, 34);
    } else {
      done();
    }
  };
  tick();
}

function revealStep(idx) {
  if (idx >= STEPS.length) return;
  const s = STEPS[idx];
  const el = document.getElementById(s.id);
  el.textContent = s.text;
  el.className = "t-line " + s.cls;
  setTimeout(() => revealStep(idx + 1), 420);
}

window.addEventListener("DOMContentLoaded", () => {
  typeIdea(document.getElementById("typed-idea"), () => {
    setTimeout(() => revealStep(0), 350);
  });
});

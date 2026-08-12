/* RBLX OPERATOR — site script (zero deps).
   Terminal typing animation + staged pipeline output. */

"use strict";

const IDEA = "zombie survival in a cursed mall, 10 waves";
const STEPS = [
  { id: "t1", text: "operator: goal → rounds, win by wave 10 · 6 enemy types", cls: "t-dim" },
  { id: "t2", text: "craft: sound identity + lighting mood · storm-dusk horror", cls: "t-dim" },
  { id: "t3", text: "codegen: emitted src/shared/config.luau — typed, balanced", cls: "t-dim" },
  { id: "t4", text: "verify: 25 files · --!strict · block balance · PASS", cls: "t-dim" },
  { id: "t5", text: "✔ SHIPPED → ZombieMall.rbxl · open in Studio? y", cls: "t-ok" },
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
  setTimeout(() => revealStep(idx + 1), 460);
}

window.addEventListener("DOMContentLoaded", () => {
  typeIdea(document.getElementById("typed-idea"), () => {
    setTimeout(() => revealStep(0), 380);
  });
});

/* RBLX OPERATOR — site script (zero deps).
   ASCII BUILDER BOI reveal, terminal typing animation, copy-to-clipboard. */

"use strict";

const ASCII = [
  "                       X:+::X",
  "                  $$**x* ·· *x**$$",
  "                $**X&$$X++++X$$&X**$",
  "               X:X$XXxXXXxxxXXxXX$X+x",
  "              x:XXxX&X*xxxxxx*X&XxXX+x",
  "            $*X*XX*&&X********X&&*XX*X*$",
  "            $+$++:·:...      ...:··++$*X",
  "            +·     ..··········..     ·+",
  "            $x.*xxXXXXXXXXXXXXXXXXxx*.x$",
  "             $·xXX++XXXXXXXXXXXX++XXX·$",
  "             $·xXXXx************xXXXX·$",
  "             $·xXXXXXXXXXXXXXXXXXXXXx·$",
  "             $·xXXXXXXXXXXXXXXXXXXXXx·$",
  "             $·*xXXXXXXXXXXXXXXXXXXx*·$",
  "              x·*xxxXXXXXXXXXXXXxxx*·X",
  "               $*+:+***xxxxxx***+::*$",
  "                  $$XXxxxxxxxxXx$$",
  "",
];

const IDEA = "zombie survival in a cursed mall, 10 waves";
const STEPS = [
  { id: "t1", text: "opencode · rblx-designer agent armed — free Zen tier", cls: "t-dim" },
  { id: "t2", text: "craft: sound identity + lighting mood · storm-dusk horror", cls: "t-dim" },
  { id: "t3", text: "codegen: emitted src/shared/config.luau — typed, balanced", cls: "t-dim" },
  { id: "t4", text: "verify: 27 files · --!strict · block balance · PASS", cls: "t-dim" },
  { id: "t5", text: "✔ SHIPPED → ZombieMall.rbxl · open in Studio? y", cls: "t-ok" },
];

function renderAscii(el) {
  ASCII.forEach((line, i) => {
    const span = document.createElement("span");
    span.textContent = line || " ";
    span.style.animationDelay = (i * 40) + "ms";
    el.appendChild(span);
  });
}

function typeIdea(el, done) {
  let i = 0;
  const tick = () => {
    if (i <= IDEA.length) {
      el.textContent = IDEA.slice(0, i);
      i += 1;
      setTimeout(tick, 30);
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

function wireCopy() {
  document.querySelectorAll(".copy[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy");
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = "copied";
        btn.classList.add("done");
        setTimeout(() => {
          btn.textContent = "copy";
          btn.classList.remove("done");
        }, 1600);
      } catch {
        btn.textContent = "select";
      }
    });
  });
}

window.addEventListener("DOMContentLoaded", () => {
  renderAscii(document.getElementById("ascii-art"));
  wireCopy();
  setTimeout(() => {
    typeIdea(document.getElementById("typed-idea"), () => {
      setTimeout(() => revealStep(0), 300);
    });
  }, 350);
});

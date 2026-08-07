/* Seaty marketing site — decorative animation setup (staggered delays only;
   the actual motion is defined in css/animations.css so it stays paused
   automatically under prefers-reduced-motion). */

(function () {
  "use strict";

  function stagger(selector, varName) {
    document.querySelectorAll(selector).forEach(function (el, i) {
      el.style.setProperty(varName, i);
    });
  }

  stagger(".seat-grid .seat", "--d");
  stagger(".toast-stack .toast", "--d");

  /* Stagger .reveal children inside a .reveal-group so sections cascade in */
  document.querySelectorAll(".reveal-group").forEach(function (group) {
    group.querySelectorAll(".reveal").forEach(function (el, i) {
      el.style.setProperty("--reveal-delay", i * 90 + "ms");
    });
  });
})();

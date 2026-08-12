/* Seaty marketing site — shared UI behaviour: nav, scroll-reveal, accordion, counters. */

(function () {
  "use strict";

  var header = document.querySelector(".site-header");
  var navToggle = document.querySelector(".nav-toggle");
  var navPanel = document.querySelector(".nav-mobile-panel");

  /* Sticky header shadow on scroll */
  if (header) {
    var onScroll = function () {
      header.classList.toggle("is-scrolled", window.scrollY > 8);
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* Mobile nav toggle */
  if (navToggle && navPanel) {
    navToggle.addEventListener("click", function () {
      var isOpen = navPanel.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", String(isOpen));
      document.body.style.overflow = isOpen ? "hidden" : "";
    });

    navPanel.querySelectorAll(".nav-link").forEach(function (link) {
      link.addEventListener("click", function () {
        navPanel.classList.remove("is-open");
        navToggle.setAttribute("aria-expanded", "false");
        document.body.style.overflow = "";
      });
    });
  }

  /* Highlight the current page in nav */
  var currentPath = window.location.pathname.split("/").pop() || "index.html";
  document.querySelectorAll(".nav-link").forEach(function (link) {
    var href = link.getAttribute("href");
    if (href === currentPath || (currentPath === "" && href === "index.html")) {
      link.classList.add("is-active");
    }
  });

  /* Scroll-reveal via IntersectionObserver */
  var revealEls = document.querySelectorAll(".reveal");
  var prefersReducedMotion = window.matchMedia(
    "(prefers-reduced-motion: reduce)"
  ).matches || document.body.classList.contains("static-page");

  /* Pause SVG SMIL animations for static pages */
  if (document.body.classList.contains("static-page")) {
    document.querySelectorAll("svg").forEach(function (svg) {
      if (typeof svg.pauseAnimations === "function") {
        svg.pauseAnimations();
      }
    });
  }

  if (revealEls.length) {
    if (prefersReducedMotion || !("IntersectionObserver" in window)) {
      revealEls.forEach(function (el) {
        el.classList.add("is-visible");
      });
    } else {
      var revealObserver = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-visible");
              revealObserver.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.18, rootMargin: "0px 0px -40px 0px" }
      );
      revealEls.forEach(function (el) {
        revealObserver.observe(el);
      });
    }
  }

  /* Count-up stats */
  var counters = document.querySelectorAll("[data-count]");
  if (counters.length && !prefersReducedMotion && "IntersectionObserver" in window) {
    var countObserver = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          var el = entry.target;
          var target = parseFloat(el.getAttribute("data-count"));
          var suffix = el.getAttribute("data-suffix") || "";
          var duration = 1400;
          var start = null;

          function step(ts) {
            if (start === null) start = ts;
            var progress = Math.min((ts - start) / duration, 1);
            var eased = 1 - Math.pow(1 - progress, 3);
            var value = Math.round(target * eased);
            el.textContent = value + suffix;
            if (progress < 1) requestAnimationFrame(step);
          }
          requestAnimationFrame(step);
          countObserver.unobserve(el);
        });
      },
      { threshold: 0.5 }
    );
    counters.forEach(function (el) {
      countObserver.observe(el);
    });
  }

  /* FAQ accordion */
  document.querySelectorAll(".accordion-trigger").forEach(function (trigger) {
    trigger.addEventListener("click", function () {
      var item = trigger.closest(".accordion-item");
      var wasOpen = item.classList.contains("is-open");
      item
        .closest(".accordion")
        .querySelectorAll(".accordion-item")
        .forEach(function (el) {
          el.classList.remove("is-open");
          el.querySelector(".accordion-trigger").setAttribute(
            "aria-expanded",
            "false"
          );
        });
      if (!wasOpen) {
        item.classList.add("is-open");
        trigger.setAttribute("aria-expanded", "true");
      }
    });
  });

  /* Role spotlight tabs (home page) */
  var roleTabs = document.querySelectorAll(".role-tab");
  if (roleTabs.length) {
    roleTabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        var target = tab.getAttribute("data-role-target");
        roleTabs.forEach(function (t) {
          t.classList.toggle("is-active", t === tab);
        });
        document.querySelectorAll(".role-panel").forEach(function (panel) {
          panel.classList.toggle("is-active", panel.getAttribute("data-role") === target);
        });
      });
    });
  }

  /* Dynamic Live Seat Booking & Mouse Hover Color Randomizer for Seaty Seat Map */
  var seatCard = document.querySelector(".seaty-seat-card-demo");
  if (seatCard) {
    var seats = seatCard.querySelectorAll(".seat-item");
    var activeCycleIndex = 0;
    var maleBadge = '<span class="gender-badge gender-badge-male"><svg viewBox="0 0 24 24" width="9" height="9" fill="none" stroke="#2563eb" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="7" r="4"/><path d="M6 21v-2a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2"/></svg></span>';
    var femaleBadge = '<span class="gender-badge gender-badge-female"><svg viewBox="0 0 24 24" width="9" height="9" fill="none" stroke="#ec4899" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="7" r="4"/><path d="M7 21l2-7h6l2 7"/><path d="M9 14h6"/></svg></span>';

    seats.forEach(function (seat) {
      seat.style.cursor = "pointer";

      /* Mouse hover color change (randomly Blue or Pink) */
      seat.addEventListener("mouseenter", function () {
        var rawNum = seat.getAttribute("data-seat") || seat.textContent.replace(/[^0-9]/g, "");
        var isMale = Math.random() > 0.5;
        if (isMale) {
          seat.className = "seat-item seat-male is-hovered";
          seat.innerHTML = rawNum + maleBadge;
        } else {
          seat.className = "seat-item seat-female is-hovered";
          seat.innerHTML = rawNum + femaleBadge;
        }
      });

      /* Click to toggle seat state */
      seat.addEventListener("click", function () {
        var rawNum = seat.getAttribute("data-seat") || seat.textContent.replace(/[^0-9]/g, "");
        if (seat.classList.contains("seat-male")) {
          seat.className = "seat-item seat-female";
          seat.innerHTML = rawNum + femaleBadge;
        } else if (seat.classList.contains("seat-female")) {
          seat.className = "seat-item seat-held";
          seat.innerHTML = rawNum;
        } else if (seat.classList.contains("seat-held")) {
          seat.className = "seat-item";
          seat.innerHTML = rawNum;
        } else {
          seat.className = "seat-item seat-male";
          seat.innerHTML = rawNum + maleBadge;
        }
      });
    });

    /* Background live booking cycle */
    if (!prefersReducedMotion) {
      setInterval(function () {
        if (!seats.length) return;
        var targetSeat = seats[activeCycleIndex % seats.length];
        var rawNum = targetSeat.getAttribute("data-seat") || targetSeat.textContent.replace(/[^0-9]/g, "");

        if (!targetSeat.classList.contains("is-hovered") && !targetSeat.classList.contains("seat-male") && !targetSeat.classList.contains("seat-female") && !targetSeat.classList.contains("seat-held")) {
          var fillMale = Math.random() > 0.45;
          if (fillMale) {
            targetSeat.className = "seat-item seat-male";
            targetSeat.innerHTML = rawNum + maleBadge;
          } else {
            targetSeat.className = "seat-item seat-female";
            targetSeat.innerHTML = rawNum + femaleBadge;
          }
        }
        activeCycleIndex++;
      }, 1600);
    }
  }

  /* Dynamic Route Selector Dropdown for Live GPS Map */
  var routeDropdown = document.getElementById("routeSelectDropdown");
  var movingBus = document.querySelector(".moving-bus-marker");
  var outerLine = document.getElementById("routeOuterLine");
  var baseLine = document.getElementById("routeBaseLine");
  var dashLine = document.getElementById("routeDashLine");
  var infoTitle = document.getElementById("infoTitle");
  var busRouteTag = document.getElementById("busRouteTag");

  if (routeDropdown) {
    var routePaths = {
      trinco: {
        path: "M 610 360 C 530 460, 450 560, 330 685",
        title: "Trincomalee ↔ Colombo Express",
        tag: "SLTB Superline"
      },
      kandy: {
        path: "M 330 685 C 400 660, 450 635, 500 615",
        title: "Colombo ↔ Kandy Highway Express",
        tag: "Kandy Express"
      },
      galle: {
        path: "M 330 685 C 340 730, 370 780, 410 850",
        title: "Colombo ↔ Galle / Matara Highway",
        tag: "Southern Coach"
      }
    };

    routeDropdown.addEventListener("change", function () {
      var selected = routeDropdown.value;
      var routeData = routePaths[selected];
      if (!routeData) return;

      if (outerLine) outerLine.setAttribute("d", routeData.path);
      if (baseLine) baseLine.setAttribute("d", routeData.path);
      if (dashLine) dashLine.setAttribute("d", routeData.path);
      if (movingBus) movingBus.style.offsetPath = 'path("' + routeData.path + '")';
      if (infoTitle) infoTitle.textContent = routeData.title;
      if (busRouteTag) busRouteTag.textContent = routeData.tag;
    });
  }

  /* Footer year */
  var yearEl = document.getElementById("current-year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();

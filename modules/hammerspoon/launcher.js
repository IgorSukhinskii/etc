// ── state ──────────────────────────────────────────────────────────────
let allApps = [];
let filtered = [];
let selectedIndex = 0;
const iconCache = {}; // path → data URL

const input = document.getElementById("input");
const results = document.getElementById("results");

const MAX_VISIBLE = 50;

// ── fuzzy match ───────────────────────────────────────────────────────
function fuzzyScore(query, text) {
  const lq = query.toLowerCase();
  const lt = text.toLowerCase();
  let qi = 0;
  let score = 0;
  let lastMatch = -1;

  for (let ti = 0; ti < lt.length && qi < lq.length; ti++) {
    if (lt[ti] === lq[qi]) {
      score += 1;
      // consecutive bonus
      if (lastMatch === ti - 1) score += 3;
      // word-boundary bonus
      if (ti === 0 || lt[ti - 1] === " " || lt[ti - 1] === "-" || lt[ti - 1] === "_") score += 5;
      // gap penalty: favor tighter matches
      if (lastMatch >= 0 && ti - lastMatch > 1) score -= 1;
      lastMatch = ti;
      qi++;
    }
  }

  if (qi < lq.length) return -1; // not all chars matched
  return score;
}

function filterApps(query) {
  if (!query) return allApps.slice(0, MAX_VISIBLE);

  const scored = [];
  for (const app of allApps) {
    const s = fuzzyScore(query, app.name);
    if (s >= 0) scored.push({ app, score: s });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, MAX_VISIBLE).map((s) => s.app);
}

// ── rendering ─────────────────────────────────────────────────────────
function renderResults() {
  results.innerHTML = "";
  for (let i = 0; i < filtered.length; i++) {
    const app = filtered[i];
    const div = document.createElement("div");
    div.className = "item" + (i === selectedIndex ? " selected" : "");

    const img = document.createElement("img");
    img.className = "item-icon";
    img.dataset.path = app.path;
    if (iconCache[app.path]) img.src = iconCache[app.path];
    div.appendChild(img);

    const text = document.createElement("div");
    text.className = "item-text";

    const name = document.createElement("div");
    name.className = "item-name";
    name.textContent = app.name;

    const path = document.createElement("div");
    path.className = "item-path";
    path.textContent = app.path;

    text.appendChild(name);
    text.appendChild(path);
    div.appendChild(text);
    div.addEventListener("click", () => launchApp(app));
    results.appendChild(div);
  }
  scrollSelectedIntoView();
}

function scrollSelectedIntoView() {
  const sel = results.querySelector(".item.selected");
  if (sel) sel.scrollIntoView({ block: "nearest" });
}

function updateSelection(oldIndex, newIndex) {
  const items = results.children;
  if (items[oldIndex]) items[oldIndex].classList.remove("selected");
  if (items[newIndex]) items[newIndex].classList.add("selected");
  selectedIndex = newIndex;
  scrollSelectedIntoView();
}

function launchApp(app) {
  webkit.messageHandlers.launcher.postMessage(
    JSON.stringify({ action: "launch", path: app.path })
  );
}

// ── keyboard handling ─────────────────────────────────────────────────
input.addEventListener("input", () => {
  filtered = filterApps(input.value);
  selectedIndex = 0;
  renderResults();
});

document.addEventListener("keydown", (e) => {
  if (e.key === "ArrowDown") {
    e.preventDefault();
    if (selectedIndex < filtered.length - 1) {
      updateSelection(selectedIndex, selectedIndex + 1);
    }
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    if (selectedIndex > 0) {
      updateSelection(selectedIndex, selectedIndex - 1);
    }
  } else if (e.key === "Enter") {
    e.preventDefault();
    if (filtered[selectedIndex]) {
      launchApp(filtered[selectedIndex]);
    }
  } else if (e.key === "Escape") {
    e.preventDefault();
    webkit.messageHandlers.launcher.postMessage(
      JSON.stringify({ action: "hide" })
    );
  }
});

// ── API (called from Lua) ─────────────────────────────────────────────
window.setTheme = function (colors) {
  const root = document.documentElement.style;
  for (const [key, value] of Object.entries(colors)) {
    root.setProperty("--" + key, value);
  }
};

window.loadApps = function (apps) {
  allApps = apps;
  filtered = filterApps(input.value);
  selectedIndex = 0;
  renderResults();
};

window.loadIcons = function (icons) {
  // Merges new icons into cache. Old entries are harmless (app list is stable).
  Object.assign(iconCache, icons);
  // patch src on already-rendered items without a full re-render
  document.querySelectorAll(".item-icon[data-path]").forEach((img) => {
    const url = iconCache[img.dataset.path];
    if (url && !img.src) img.src = url;
  });
};

window.activate = function () {
  input.value = "";
  filtered = allApps.slice(0, MAX_VISIBLE);
  selectedIndex = 0;
  renderResults();
  input.focus();
};

// Fires once at startup. The webview is created once and never reloaded,
// so this won't re-trigger. If reload behavior changes, guard in Lua.
webkit.messageHandlers.launcher.postMessage(JSON.stringify({ action: "ready" }));

const root = document.body.dataset.root;
const search = document.querySelector("#docs-search");
if (search) {
  let entries;
  let request;
  let queryVersion = 0;
  const results = document.querySelector("#search-results");
  const status = document.querySelector("#search-status");
  search.addEventListener("input", async () => {
    const version = ++queryVersion;
    const query = search.value.trim().toLowerCase();
    results.replaceChildren();
    status.textContent = "";
    if (!query) {
      return;
    }
    try {
      request ??= fetch(`${root}search.json`).then((response) => {
        if (!response.ok) {
          throw new Error("Search unavailable");
        }
        return response.json();
      });
      entries ??= await request;
      if (version !== queryVersion) {
        return;
      }
      const words = query.split(/\s+/);
      const matches = entries.filter((entry) =>
        words.every((word) => `${entry.title} ${entry.text}`.toLowerCase().includes(word)),
      );
      matches.sort(
        (a, b) =>
          Number(b.title.toLowerCase().includes(query)) -
          Number(a.title.toLowerCase().includes(query)),
      );
      status.textContent = matches.length
        ? `${matches.length} documents found. Showing up to 20.`
        : "No documents found. Try graphics, audio, or cartridges.";
      for (const entry of matches.slice(0, 20)) {
        const item = document.createElement("li");
        const link = document.createElement("a");
        link.href = `${root}${entry.url}`;
        link.textContent = entry.title;
        const excerpt = document.createElement("small");
        const position = Math.max(0, entry.text.toLowerCase().indexOf(words[0]) - 40);
        excerpt.textContent = `${entry.text.slice(position, position + 160)}…`;
        link.append(excerpt);
        item.append(link);
        results.append(item);
      }
    } catch {
      request = null;
      status.textContent =
        "Search could not load. Browse the documentation links below, or try again.";
    }
  });
}

const launchScreen = document.querySelector(".launch-screen");
if (launchScreen) {
  const language = document.querySelector("#language");
  const slot = document.querySelector("#player-slot");
  const restart = document.querySelector("#restart");
  const download = document.querySelector("#download");
  const status = document.querySelector("#play-status");
  const { game, cartridge, gpu } = launchScreen.dataset;
  let launched = false;
  let timer;
  function load() {
    clearTimeout(timer);
    if (gpu === "true" && !navigator.gpu) {
      status.textContent =
        "This game requires a GPU-capable browser. Try a supported desktop browser.";
      return;
    }
    launched = true;
    const frame = document.createElement("iframe");
    frame.title = `${game} game player`;
    frame.allow = "autoplay; fullscreen";
    frame.src = `${root}games/${game}/player.html?game=./${cartridge}-${language.value}.png&renderer=cpu&ssaa=off`;
    status.textContent = "Loading cartridge…";
    frame.addEventListener("load", () => {
      const deadline = Date.now() + 60000;
      function check() {
        const state = frame.contentWindow?.playerStatus;
        if (state?.error) {
          status.textContent = `The player could not start: ${state.error}. Use Restart game to retry.`;
        } else if (state?.ready) {
          status.textContent =
            "Ready. Press Start game for sound. Touch controls are below the display.";
        } else if (Date.now() > deadline) {
          status.textContent =
            "The player is taking longer than expected. Use Restart game to retry.";
        } else {
          timer = setTimeout(check, 250);
        }
      }
      check();
    });
    slot.replaceChildren(frame);
    slot.hidden = false;
    launchScreen.hidden = true;
    restart.hidden = false;
  }
  document.querySelector("#launch").addEventListener("click", load);
  restart.addEventListener("click", load);
  language.addEventListener("change", () => {
    download.href = `${root}games/${game}/${cartridge}-${language.value}.png`;
    if (launched) {
      load();
    }
  });
}

const gameFilters = document.querySelectorAll("[data-filter]");
for (const button of gameFilters) {
  button.addEventListener("click", () => {
    for (const option of gameFilters) {
      option.setAttribute("aria-pressed", String(option === button));
    }
    for (const card of document.querySelectorAll(".game-card")) {
      card.hidden =
        button.dataset.filter !== "all" && card.dataset.category !== button.dataset.filter;
    }
  });
}

import { games } from "./catalog.mjs";

export const escape = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

export function shell({ title, description, active, body, root = "./" }) {
  const nav = [
    ["Home", "index.html", "home"],
    ["Documentation", "docs/index.html", "docs"],
    ["Showcase", "showcase/index.html", "showcase"],
  ];
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${escape(description)}"><meta name="theme-color" content="#161426">
<title>${escape(title)} · Bytorio</title><link rel="icon" href="${root}assets/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="${root}site.css"><link rel="stylesheet" href="${root}retro.css"><script type="module" src="${root}site.js"></script></head>
<body data-root="${root}"><a class="skip" href="#main">Skip to content</a>
<header class="header"><a class="brand" href="${root}index.html" aria-label="Bytorio home"><span class="brand-icon" aria-hidden="true">✳</span> Bytorio<span class="preview-label">PREVIEW</span></a>
<nav aria-label="Main navigation">${nav.map(([label, href, key]) => `<a href="${root}${href}" ${active === key ? 'aria-current="page"' : ""}>${label}</a>`).join("")}</nav>
<a class="header-cta" href="${root}docs/sdk/README.html">Start creating <span aria-hidden="true">↗</span></a></header>
${body}
<footer><a class="brand" href="${root}index.html"><span class="brand-icon" aria-hidden="true">✳</span> Bytorio</a><p>Small games. Big possibilities.</p><a href="${root}docs/index.html">Read the docs ↗</a><span class="mono">BYTOR.IO / A CONSOLE IN THE MAKING</span></footer></body></html>`;
}

export function card(game, root) {
  return `<article class="game-card ${game.color}"><a class="game-image" href="${root}showcase/${game.id}/index.html"><img src="${root}assets/${game.id}.png" alt="${escape(game.title)} gameplay" width="640" height="360" loading="lazy"><span class="play-badge" aria-hidden="true">↗</span></a><div class="game-meta mono">${game.category} <span>${game.resolution}</span></div><h3><a href="${root}showcase/${game.id}/index.html">${game.title}</a></h3><p>${game.description}</p><div class="card-bottom"><span class="compatibility">${game.requiresGpu ? "GPU required" : "Desktop + mobile · Touch ready"}</span><a href="${root}showcase/${game.id}/index.html">Play game <span aria-hidden="true">→</span></a></div></article>`;
}

export function home() {
  return shell({
    title: "Small machine. Big imagination.",
    description:
      "Bytorio is a fantasy console for making small games with Luau and Odin. Play browser demos, explore the SDK, and build your own PNG cartridge.",
    active: "home",
    body: `<main id="main">
<section class="hero"><div class="hero-copy"><p class="eyebrow"><span class="status-dot"></span> SYSTEM READY. IMAGINATION REQUIRED.</p><h1>Small machine.<br>Big <em>imagination.</em></h1><p class="hero-description">For the worlds you sketched in your school notebook. The boss fights you dreamed up on the bus. Meet Bytorio, a little fantasy console for making them real.</p><div class="actions"><a class="button primary" href="showcase/index.html"><span aria-hidden="true">▶</span> PRESS START</a><a class="text-link" href="docs/sdk/README.html">I want to make a game →</a></div><p class="hero-note mono">LUAU + ODIN <span> / </span> NATIVE + WEB <span> / </span> ALL YOU</p></div>
<div class="hero-art"><div class="orbit-label mono">★ NO QUARTERS NEEDED ★</div><a class="console" href="showcase/copper-circuit/index.html" aria-label="Play Copper Circuit"><div class="console-top mono"><span>BYTORIO / PLAYER 01</span><span><i class="status-dot"></i> SYSTEM ONLINE</span></div><div class="screen-bezel"><img src="assets/copper-circuit.png" alt="Copper Circuit running on Bytorio" width="640" height="360"><span class="screen-play">▶ PLAY COPPER CIRCUIT</span></div><div class="console-bottom"><div class="dpad" aria-hidden="true">✚</div><div class="speaker" aria-hidden="true"></div><div class="console-buttons" aria-hidden="true"><i>Y</i><i>X</i><i>B</i><i>A</i></div></div></a><span class="art-sticker">100%<br>PLAYABLE!</span><p class="art-caption mono">↑ ↑ GOOD TIMES AHEAD ↓ ↓</p></div></section>
<div class="spec-strip"><span><b>2D first.</b> A little 3D, too.</span><span><b>Two languages.</b> One machine.</span><span><b>One PNG.</b> Your whole game.</span><span><b>Made to play.</b> Built to tinker.</span></div>
<section class="section"><div class="section-heading"><div><p class="eyebrow">THE GOOD KIND OF LIMITS</p><h2>A little console.<br>A lot to play with.</h2></div><p>Skip the sprawling engine. Find your idea, open your favorite editor, and bring a small world to life.</p></div><div class="feature-grid"><article><span class="feature-symbol">▦</span><span class="mono">01 / PICTURE</span><h3>Pixels with personality.</h3><p>Sprites, textures, and crisp 640 × 360 or 320 × 180 displays. Start in 2D, then explore the experimental low-poly 3D profile.</p><a href="docs/sdk/graphics.html">Explore graphics ↗</a></article><article><span class="feature-symbol">⌘</span><span class="mono">02 / PROCESS</span><h3>Your editor. Your rhythm.</h3><p>Write in typed Luau or Odin. Check, build, and watch through one CLI, with the same cartridge running on native and web players.</p><a href="docs/sdk/README.html">Meet the SDK ↗</a></article><article><span class="feature-symbol">▣</span><span class="mono">03 / PLAY</span><h3>A game you can pass around.</h3><p>Pack your creation into a viewable PNG cartridge. Load the original file in a compatible player and let someone else take a turn.</p><a href="docs/docs/png-cartridges.html">Inside a cartridge ↗</a></article></div></section>
<section class="section games-section"><div class="section-heading"><div><p class="eyebrow">SELECT CARTRIDGE / PRESS PLAY</p><h2>Your next high score awaits.</h2></div><a class="text-link" href="showcase/index.html">Visit the showcase ↗</a></div><div class="game-grid">${games.map((game) => card(game, "./")).join("")}</div></section>
<section class="make-section"><div><p class="eyebrow">FROM “WHAT IF” TO FIRST FRAME</p><h2>Your next game<br>starts small.</h2><p>A folder, a few lines of code, and something that moves.<br>The docs will take it from there.</p><a class="button dark" href="docs/sdk/README.html">Let’s make a game ↗</a></div><div class="terminal"><div class="terminal-bar"><span>● ● ●</span><span>YOUR NEXT PROJECT</span></div><pre><span class="comment"># Make a little room for a big idea</span>\nmise exec -- npm run console -- new my-game\n\n<span class="comment"># Bring it to the browser</span>\nmise exec -- npm run console -- run my-game --web</pre><p>Windows x64 development · Pinned toolchain via mise</p></div></section></main>`,
  });
}

export function showcase() {
  return shell({
    title: "The showcase",
    description:
      "Play complete Bytorio demos in your browser, with keyboard and mobile touch controls.",
    active: "showcase",
    root: "../",
    body: `<main id="main"><section class="page-intro"><p class="eyebrow">WELCOME TO THE CARTRIDGE CLUB</p><h1>Choose your<br><em>next adventure.</em></h1><p>Small games. Big “one more go” energy.<br>Pick a cartridge, press start, and get wonderfully sidetracked.</p></section><section class="section showcase-list"><div class="shelf-bar"><span class="mono">02 CARTRIDGES / ALL SYSTEMS GO</span><span>Keyboard or touch. No install needed.</span></div><div class="game-grid">${games.map((game) => card(game, "../")).join("")}</div><aside class="note">Both demos use the CPU renderer and do not require WebGPU. Browser performance varies by device. Experimental GPU features are documented separately.</aside></section></main>`,
  });
}

export function gamePage(game) {
  return shell({
    title: game.title,
    description: game.description,
    active: "showcase",
    root: "../../",
    body: `<main id="main" class="game-page"><a class="back-link" href="../index.html">← Back to the showcase</a><div class="game-title"><div><p class="eyebrow">${game.category} / ${game.resolution}</p><h1>${game.title}</h1></div><span class="compatibility">${game.requiresGpu ? "GPU required" : "Desktop + mobile · CPU renderer"}</span></div><div class="play-layout"><section class="play-panel" aria-label="Game player"><div class="launch-screen" data-game="${game.id}" data-cartridge="${game.cartridge}" data-gpu="${game.requiresGpu}"><img src="../../assets/${game.id}.png" alt="${game.title} preview" width="640" height="360"><div class="launch-overlay"><button class="button primary" id="launch">▶ Load game</button><p>No download. Your next few minutes, sorted.</p></div></div><div id="player-slot" hidden></div><div class="player-toolbar"><label for="language">Cartridge language</label><select id="language"><option value="luau">Luau</option><option value="odin">Odin</option></select><button id="restart" hidden>Restart game</button><a id="download" href="../../games/${game.id}/${game.cartridge}-luau.png" download>↓ PNG cartridge</a></div><p id="play-status" role="status">Load the game, then press Start game to enable audio.</p></section><aside class="game-about"><p class="eyebrow">HOW TO PLAY</p><h2>A little field guide.</h2><p>${game.detail}</p><h3>At your desk</h3><p>${game.controls}</p><h3>On the go</h3><p>Use the on-screen direction pad and ${game.action} button. Hold more than one control to move and act together.</p><a class="text-link" href="../../docs/${game.guide.replace(/\.md$/, ".html")}">Read the making-of & source guide ↗</a><p class="small">Each language is a separate implementation of the same game. Changing language starts a new session.</p></aside></div></main>`,
  });
}

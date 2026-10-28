export const games = [
  {
    id: "willow-junction",
    title: "Willow Junction",
    category: "Cozy management",
    description:
      "Route trains, welcome passengers, and decorate a tiny station to warm lo-fi synth beats.",
    detail:
      "Match incoming trains to Rose, Honey, or River platforms. Dispatch to the matching platform and spend tickets on flowers, benches, and lanterns. There is no failure timer.",
    build: "build/showcase-sources/willow-junction",
    repository: "https://github.com/ctxshift/willow-junction.git",
    revision: "6f99ef8f75690d595e7a1fb0dbb15f1bd91acdb2",
    cartridge: "willow-junction",
    guide: "https://github.com/ctxshift/willow-junction",
    resolution: "640 × 360",
    action: "Dispatch",
    controls:
      "Left / Right choose platform · Space dispatch · Up decorate · Down pause · WASD pan · Q music · Escape menu",
    requiresGpu: false,
    color: "orange",
  },
  {
    id: "abyssal-salvage",
    title: "Abyssal Salvage",
    category: "Survival",
    description: "Explore sunken wrecks, gather salvage, and face the leviathan in the deep.",
    detail:
      "Survive five minutes, defeat the leviathan that arrives at four minutes, then return to the central submarine. Harpoons fire automatically. Gather green salvage for upgrades and gold caches to repair your suit.",
    build: "build/showcase-sources/abyssal-salvage",
    repository: "https://github.com/ctxshift/abyssal-salvage.git",
    revision: "a99b96b31cae06f590f87f3c951036813d4a0911",
    cartridge: "abyssal-salvage",
    guide: "https://github.com/ctxshift/abyssal-salvage",
    resolution: "640 × 360",
    action: "Sonar",
    controls:
      "WASD / arrows move · Mouse aim light · Space start / sonar / confirm · Left / Right choose upgrade · I map · Escape pause",
    requiresGpu: false,
    color: "green",
  },
];

export const sections = [
  [
    "Start here",
    [
      ["docs/getting-started.md", "Getting started"],
      ["sdk/README.md", "SDK & supported features"],
      ["GLOSSARY.md", "Glossary"],
    ],
  ],
  [
    "Build your game",
    [
      ["sdk/api.md", "API reference"],
      ["sdk/resources.md", "Resources"],
      ["sdk/graphics.md", "Graphics"],
      ["sdk/audio.md", "Audio"],
      ["sdk/synthesis.md", "Synthesis & effects"],
      ["sdk/save.md", "Save progress"],
      ["sdk/text-input.md", "Text input"],
      ["sdk/web-player.md", "Embed the web player"],
      ["sdk/web-runtime.md", "Build a custom player"],
      ["docs/native-player.md", "Native player"],
      ["docs/display-modes.md", "Display modes"],
      ["docs/png-cartridges.md", "PNG cartridges"],
    ],
  ],
  [
    "Advanced game features",
    [
      ["docs/frame-pacing.md", "Frame pacing"],
      ["docs/model-import.md", "Import models"],
      ["docs/indexed-content.md", "Packaged content"],
    ],
  ],
  [
    "For contributors",
    [
      ["docs/contributing.md", "Low-level documentation"],
      ["docs/development.md", "Build & test the console"],
      ["docs/language-examples.md", "Conformance examples"],
      ["docs/resource-profile.md", "Profile contracts"],
      ["docs/resource-av-spec.md", "Resource specification"],
      ["docs/cartridge-spec.md", "Legacy cartridge ABI"],
      ["docs/compact-3d.md", "3D renderer reference"],
    ],
  ],
];

// Publication is opt-in. Repository notes, ADRs and benchmark reports are not
// part of the game developer handbook, even when a public guide links to them.
export const publicDocuments = [
  ...sections.flatMap(([, links]) => links.map(([path]) => path)),
  "sdk/save.md",
  "sdk/text-input.md",
  "docs/3d-effects.md",
  "docs/billboards.md",
  "docs/indexed-content.md",
  "docs/resource-av-spec.md",
  "docs/textured-3d.md",
  "docs/mise-installation.md",
];

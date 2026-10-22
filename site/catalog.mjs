export const games = [
  {
    id: "copper-circuit",
    title: "Copper Circuit",
    category: "Arcade racing",
    description:
      "Six rivals. Three laps. One well-timed boost. Take the racing line through a winding, sprite-built circuit.",
    detail:
      "Accelerate into a three-lap race, manage your rechargeable boost, and keep your kart on the road. Cross the finish line, then press Boost to race again.",
    build: "examples/racing/build/player",
    cartridge: "racing",
    guide: "docs/racing-demo.md",
    resolution: "320 × 180",
    action: "Boost",
    controls: "↑ / W accelerate · ↓ / S brake · ← → / A D steer · Space boost / restart",
    requiresGpu: false,
    color: "orange",
  },
  {
    id: "mossglen",
    title: "Mossglen: The Sunleaf",
    category: "Tiny adventure",
    description:
      "A village, a missing sunleaf, and a slime in your way. A little quest with a whole lot of heart.",
    detail:
      "Find the healer by the red house, accept the quest, and cross the eastern bridge. Defeat the moss slime, collect the sunleaf, and bring it home. In battle, choose Attack, Guard, or a healing potion.",
    build: "examples/rpg/build/player",
    cartridge: "rpg",
    guide: "docs/rpg-comparison.md",
    resolution: "640 × 360",
    action: "Confirm",
    controls: "Arrows / WASD move · Space talk / confirm · Arrows select in battle",
    requiresGpu: false,
    color: "green",
  },
];

export const sections = [
  [
    "Start here",
    [
      ["sdk/README.md", "Quick start"],
      ["docs/development.md", "Development setup"],
      ["docs/language-examples.md", "Language examples"],
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
      ["docs/display-modes.md", "Display modes"],
      ["docs/png-cartridges.md", "PNG cartridges"],
    ],
  ],
  [
    "Explore the machine",
    [
      ["docs/frame-pacing.md", "Frame pacing"],
      ["docs/compact-3d.md", "Experimental 3D"],
      ["docs/resource-profile.md", "Profiles & limits"],
      ["docs/cartridge-spec.md", "Cartridge specification"],
      ["docs/architecture.md", "Architecture"],
    ],
  ],
];

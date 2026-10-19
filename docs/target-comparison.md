# DS or 3DS as the quality target?

Research date: 2026-10-19. Status: recommendation; no change to the agreed display or cartridge sizes.

## Recommendation

Keep the initial target **DS-inspired production scope with modern conveniences**: mostly 2D, occasional textured 3D, a single 384×216 display, and small games. Allow artists to pursue a cleaner or more detailed look where the measured budgets permit. Do not promise broad 3DS-level 3D capability in version one.

This is a product and implementation recommendation, not a claim that contemporary hosts cannot render such games. Luau with a shared C++ runtime, compiled to native and WebAssembly, does not inherently restrict the project to either historical console's graphics. The first reference games and the minimum supported host must establish practical limits.

## Display comparison

| Reference | Display facts | Meaning for this project |
|---|---|---|
| Nintendo DS | Two 256×192 screens; the lower screen accepts touch input. | A historical reference for compact game production, not a display layout to reproduce. |
| Nintendo 3DS family | Stereoscopic models list an 800×240 upper panel, allocating 400×240 to each eye; the lower screen is 320×240. | Compare a single ordinary view with 400×240, not with an 800×240 game image. |
| Agreed fantasy console | One 384×216 screen, mostly 2D with occasional 3D. | Retain this specification while testing the renderer and game workflow. |

Historical display facts: [Nintendo DS specifications](https://www.nintendo.co.jp/ds/spec/index.html), [Nintendo 3DS family specifications](https://www.nintendo.co.jp/hardware/3dsseries/specs/index.html).

At 384×216, the framebuffer contains 82,944 pixels: 86.4% of a 400×240 view's 96,000 pixels. Its aspect ratio is 16:9 rather than 5:3. These are calculations from the chosen resolution and Nintendo's published 3DS dimensions; they show that the selected display is already close in pixel count to a 3DS upper-screen view. They do not establish comparable visual quality or performance. Stereo would also require rendering distinct eye views, a capability outside the current plan.

## What a higher fidelity target would change

The following describes proposed product scope, not measured historical hardware limits.

| Area | Recommended first release | If broader 3DS-inspired 3D becomes a goal |
|---|---|---|
| Main workflow | Sprites, tilemaps, UI, particles, compact 3D scenes | More sustained use of animated 3D worlds and characters |
| Renderer | Textured meshes, depth, vertex colors, simple lighting and fog | Evaluate richer materials, lighting, transparency and effects against reference scenes |
| Asset tools | Reliable image, map, audio and basic mesh import | More animation, material, model-validation and scene-authoring support |
| Performance work | Establish budgets using mostly 2D games with occasional 3D | Establish additional animated-character and environment workloads |
| Content production | Small teams can complete representative games | More modeling, rigging, animation and asset iteration may be needed |

Higher visual ambition expands both engine work and game-production work. Screen resolution and package size alone cannot define fidelity: animation, geometry, materials, effects, art direction and authoring support also matter. The agreed approximately 128 MB typical and 512 MB maximum package sizes remain distribution goals; they are not evidence of a particular console generation's capabilities.

## Revisit after reference games

Build the first mixed 2D/3D game and measure native and browser performance on an explicitly chosen minimum host. Add a second reference scene with an animated textured character, an environment, transparency, UI and audio. Measure frame time, decoded resident assets, allocation pauses and authoring friction before selecting any additional rendering features or budgets.

Keep renderer internals and asset formats extensible, but avoid reserving a promised higher machine profile. A later version could add specific features with documented compatibility rules if those workloads justify them. That decision would need explicit scope approval; the current plan retains the accepted resolution, rendering emphasis and package sizes.

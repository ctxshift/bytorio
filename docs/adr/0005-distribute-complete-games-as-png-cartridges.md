# Distribute complete games as PNG cartridges

Package a game's program and required assets in private ancillary chunks of a
viewable PNG, so one shareable file contains both cover art and the complete game.
Keep game data independent of cover pixels and the reusable player runtime;
players read bounded payload bytes without decoding the cover image.
Sharing must preserve the original file because image re-encoding can remove
the game payload.

Container details: [PNG cartridges](../png-cartridges.md).

# Provide a standalone native player

Ship a native player that runs without a webview, Node.js, or the author's
development toolchain, so playing a game does not require installing its build
environment or embedding a browser.
Keep native windowing, input, storage and device delivery in platform adapters
around the shared console runtime; maintaining those adapters is the cost of a
standalone native experience alongside the browser player.

Build and distribution details: [development guide](../development.md).

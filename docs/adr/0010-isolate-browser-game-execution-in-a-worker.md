# Isolate browser game execution in a Worker

Run browser game execution in a Worker with bounded messages and an external
watchdog, so runaway game code can be terminated without trapping the page's
controls in the same execution loop.
Keep the baseline player usable without shared memory or cross-origin isolation,
accepting message-transfer overhead to support ordinary static hosting.
Terminating a Worker discards session state and is a recovery mechanism, not a
portable instruction quota.

Watchdog and isolation: [browser host](../odin-development.md#browser) and
[supported targets](../resource-profile.md#verification-and-supported-targets).

# Declare stable save identity explicitly

Allow cartridges to declare a stable save identity so compatible code, artwork
and filename changes can retain the same save slot.
Sharing depends on that explicit identity rather than titles or paths;
cartridges without a declaration remain isolated by their content hash.
Game authors must choose distinct identities for unrelated games or incompatible
save formats, trading automatic per-build isolation for deliberate compatibility.

Identity and migration rules: [save slots](../../sdk/save.md).

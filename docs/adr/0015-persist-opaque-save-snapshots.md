# Persist opaque save snapshots

Give each cartridge one bounded save slot containing opaque bytes, with games
owning serialization, format versioning and migration rather than accessing host
files directly.
Replace complete snapshots and keep reads on the last committed snapshot until
a write succeeds, so pending or failed storage operations cannot expose partial
game records.
Report storage completion and failure explicitly instead of treating an accepted
write request as a successful save.

Persistence contract: [save slots](../../sdk/save.md).

# Keep immutable cartridge content outside guest memory

Store large immutable game blobs in a host-owned cartridge index addressed by
numeric IDs, so content capacity does not require increasing executable or guest
memory limits.
Games copy bounded ranges into caller-owned buffers rather than receiving host
pointers, and the host retains the backing data until the cartridge is unloaded.
Account for that backing storage separately from decoded runtime resources;
indexed access does not imply network streaming or automatic asset decoding.

Content interface: [indexed cartridge content](../indexed-content.md).

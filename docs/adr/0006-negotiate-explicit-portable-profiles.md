# Negotiate explicit portable capability profiles

Define cartridge capabilities through explicit versioned profiles with fixed
portable limits, so native and browser hosts promise the same console behavior
instead of exposing whatever their hardware happens to support.
Validate the declared profile, SDK, guest ABI, resource protocol, required
features and function signatures before initialization, rejecting unsupported
combinations instead of silently upgrading or reducing capabilities.
Version these compatibility boundaries separately so a container change does
not automatically redefine the game interface.

Compatibility details: [resource profiles](../resource-profile.md).

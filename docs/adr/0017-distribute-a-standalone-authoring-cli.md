# Distribute a standalone authoring CLI

Game authors should not need the console's development environment to create a
cartridge. Distribute `byt` as a standalone executable with managed, versioned
SDK dependencies, keeping mise an optional installation route rather than a
runtime requirement. This gives the CLI responsibility for compatible tooling
while preserving a simple installation path for new developers.

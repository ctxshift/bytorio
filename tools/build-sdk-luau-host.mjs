import { resolve } from "node:path";
import { produceLuauHostSdk } from "./sdk/luau-host.mjs";
import { requireCliHost } from "./host-platform.mjs";
import { tool } from "./toolchain.mjs";

const [base, output] = process.argv.slice(2);
if (!base || !output || process.argv.length !== 4) {
  throw new Error("Expected: build-sdk-luau-host <canonical candidate> <new output>");
}
await produceLuauHostSdk({
  base: resolve(base),
  output: resolve(output),
  host: requireCliHost().id,
  analyzer: tool("luau-analyze"),
});

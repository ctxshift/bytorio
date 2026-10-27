import { readFile } from "node:fs/promises";
import { unpackComponent } from "../sdk/component.mjs";
import { resolveComponent } from "./component-cache.mjs";
import { parseSdkManifest, sdkCompatibility } from "./sdk-manifest.mjs";

try {
  const request = JSON.parse(await readFile(process.argv[2], "utf8"));
  if (request.operation === "manifest") {
    const manifest = parseSdkManifest(
      Buffer.from(JSON.stringify(request.manifest)),
      request.version,
    );
    const incompatible = sdkCompatibility(manifest, request.requirements);
    if (incompatible) {
      throw new Error(incompatible);
    }
    console.log(JSON.stringify({ version: manifest.version, profile: manifest.defaults.profile }));
    process.exit(0);
  }
  const result =
    request.operation === "resolve"
      ? await resolveComponent(request.component, request.options)
      : { inventory: await unpackComponent(request) };
  console.log(
    JSON.stringify({
      files: result.inventory.files.length,
      notices: result.inventory.notices,
      ...(result.directory ? { directory: result.directory } : {}),
    }),
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

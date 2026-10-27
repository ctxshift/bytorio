import { readFile } from "node:fs/promises";
import { unpackComponent } from "../sdk/component.mjs";
import { resolveComponent } from "./component-cache.mjs";

try {
  const request = JSON.parse(await readFile(process.argv[2], "utf8"));
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

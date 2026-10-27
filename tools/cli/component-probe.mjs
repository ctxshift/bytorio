import { readFile } from "node:fs/promises";
import { unpackComponent } from "../sdk/component.mjs";

try {
  const request = JSON.parse(await readFile(process.argv[2], "utf8"));
  const inventory = await unpackComponent(request);
  console.log(JSON.stringify({ files: inventory.files.length, notices: inventory.notices }));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

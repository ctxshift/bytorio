import { readFileSync, writeFileSync } from "node:fs";
import { formatSource, sourceFiles } from "./code-tools.mjs";

const args = process.argv.slice(2);
if (args.some((arg) => !["--check", "odin", "luau"].includes(arg))) {
  throw new Error("Usage: node tools/format-code.mjs [--check] [odin|luau]");
}
const check = args.includes("--check");
const languages = args.filter((arg) => arg !== "--check");
const files = (languages.length ? languages : ["odin", "luau"]).flatMap((language) =>
  sourceFiles(`.${language}`),
);
let changed = 0;
for (const file of files) {
  const original = readFileSync(file, "utf8");
  const formatted = formatSource(original, file);
  if (original.replaceAll("\r\n", "\n") !== formatted) {
    changed++;
    console.log(`${check ? "Needs formatting" : "Formatted"}: ${file}`);
    if (!check) {
      writeFileSync(file, formatted);
    }
  }
}
console.log(
  `${files.length} Odin/Luau files checked; ${changed} ${check ? "need formatting" : "formatted"}.`,
);
if (check && changed) {
  process.exitCode = 1;
}

import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { compileCli } from "./compile-cli.mjs";
import { requireCliHost } from "./host-platform.mjs";
import { repo } from "./toolchain.mjs";
import { packComponent } from "./sdk/component.mjs";

const output = resolve(repo, "build/sdk-component-verification");
await mkdir(output, { recursive: true });
const host = requireCliHost();
const built = resolve(output, host.executable);
compileCli(["tools/cli/component-probe.mjs"], built);
const temporaryRoot = resolve(tmpdir());
const sandbox = await mkdtemp(resolve(temporaryRoot, "byt-component-consumer-"));
assert.ok(sandbox.startsWith(temporaryRoot + sep));
try {
  const executable = resolve(sandbox, host.executable);
  await copyFile(built, executable);
  const payload = resolve(sandbox, "SDK payload");
  await mkdir(resolve(payload, "licenses"), { recursive: true });
  const binary = Buffer.from(Array.from({ length: 256 }, (_, i) => i));
  await writeFile(resolve(payload, "tool"), binary);
  await writeFile(resolve(payload, "licenses/sdk.txt"), "SDK license notice\n");
  const archive = resolve(sandbox, "component.tar.gz");
  const descriptor = await packComponent({
    root: payload,
    archive,
    executables: ["tool"],
    notices: ["licenses/sdk.txt"],
  });
  const destination = resolve(sandbox, "installed");
  const request = resolve(sandbox, "request.json");
  await writeFile(request, JSON.stringify({ archive, destination, descriptor }));
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(([name]) => !/^(path|mise.*|node.*|bun.*)$/i.test(name)),
  );
  environment.PATH = "";
  const invoke = () =>
    spawnSync(executable, [request], {
      cwd: sandbox,
      env: environment,
      encoding: "utf8",
      windowsHide: true,
      timeout: 30000,
    });
  const success = invoke();
  assert.ifError(success.error);
  assert.equal(success.status, 0, success.stderr);
  assert.deepEqual(JSON.parse(success.stdout), { files: 2, notices: ["licenses/sdk.txt"] });
  assert.deepEqual(await readFile(resolve(destination, "tool")), binary);
  await writeFile(archive, "corrupt archive");
  const failure = invoke();
  assert.ifError(failure.error);
  assert.equal(failure.status, 1, failure.stderr);
  assert.match(failure.stderr, /checksum or size mismatch/);
  await writeFile(
    resolve(output, "report.json"),
    JSON.stringify(
      {
        status: "passed",
        platform: host.id,
        isolatedCwd: true,
        emptyPath: true,
        checks: ["binary payload", "notices", "archive integrity", "no external archiver"],
      },
      null,
      2,
    ) + "\n",
  );
  console.log("Compiled SDK component extraction passed with an isolated cwd and empty PATH.");
} finally {
  await rm(sandbox, { recursive: true, force: true });
}

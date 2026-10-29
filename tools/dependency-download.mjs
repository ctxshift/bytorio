import { createHash, randomUUID } from "node:crypto";
import { readFile, writeFile, rename, rm, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const transientCodes = new Set([
  "ECONNRESET",
  "ETIMEDOUT",
  "EAI_AGAIN",
  "ECONNREFUSED",
  "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_SOCKET",
  "UND_ERR_HEADERS_TIMEOUT",
  "UND_ERR_BODY_TIMEOUT",
]);
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");

export async function downloadDependency(
  url,
  destination,
  sha256,
  { request = fetch, wait = sleep, attempts = 3, timeoutMs = 120000 } = {},
) {
  if (
    !/^[a-f0-9]{64}$/.test(sha256) ||
    !Number.isInteger(attempts) ||
    attempts < 1 ||
    attempts > 3
  ) {
    throw new Error("Expected a SHA-256 pin and one to three download attempts");
  }
  try {
    if (digest(await readFile(destination)) !== sha256) {
      throw new Error("Cached dependency checksum mismatch; remove the corrupt archive explicitly");
    }
    return;
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  await mkdir(dirname(destination), { recursive: true });
  for (let attempt = 1; attempt <= attempts; attempt++) {
    let bytes;
    try {
      const response = await request(url, { signal: AbortSignal.timeout(timeoutMs) });
      if (!response.ok) {
        await response.body?.cancel();
        const error = new Error(`Dependency download failed: HTTP ${response.status}`);
        error.transient = [408, 429, 500, 502, 503, 504].includes(response.status);
        throw error;
      }
      bytes = Buffer.from(await response.arrayBuffer());
    } catch (error) {
      const transient =
        error.transient ||
        error.name === "TimeoutError" ||
        transientCodes.has(error.code) ||
        transientCodes.has(error.cause?.code);
      if (!transient || attempt === attempts) {
        throw error;
      }
      await wait(attempt * 1000);
      continue;
    }
    if (digest(bytes) !== sha256) {
      throw new Error("Downloaded dependency checksum mismatch");
    }
    const temporary = `${destination}.${randomUUID()}.tmp`;
    try {
      await writeFile(temporary, bytes, { flag: "wx" });
      await rename(temporary, destination);
    } finally {
      await rm(temporary, { force: true });
    }
    return;
  }
}

import { MAX_CARTRIDGE_BYTES } from "./constants.js";

const CACHE_NAME = "bytorio-cartridges-v1";
const MAX_ENTRIES = 2;

function versionedUrl(source) {
  if (source instanceof Blob) {
    return null;
  }
  try {
    const url = new URL(source, globalThis.location?.href);
    const revisions = url.searchParams.getAll("revision");
    if (
      !["http:", "https:"].includes(url.protocol) ||
      (globalThis.location && url.origin !== globalThis.location.origin) ||
      !url.pathname.toLowerCase().endsWith(".png") ||
      revisions.length !== 1 ||
      !/^[a-f0-9]{64}$/.test(revisions[0])
    ) {
      return null;
    }
    url.hash = "";
    return url;
  } catch {
    return null;
  }
}

function decodedLength(response) {
  const encoding = response.headers.get("content-encoding");
  const length = response.headers.get("content-length");
  if ((encoding && encoding !== "identity") || !/^\d+$/.test(length || "")) {
    return 0;
  }
  const result = Number(length);
  return Number.isSafeInteger(result) ? result : MAX_CARTRIDGE_BYTES + 1;
}

// This helper intentionally does not clone/tee the response. A slow cache
// consumer could otherwise accumulate a whole cartridge behind the player.
// Storage consumes the network stream first, then the player reads its copy.
export async function fetchCartridge(source, options = {}) {
  if (source instanceof Blob) {
    return source;
  }
  const fetchResponse = options.fetchResponse || globalThis.fetch;
  const url = versionedUrl(source);
  if (!url) {
    return fetchResponse(source);
  }
  let storage, cache;
  try {
    storage = options.cacheStorage === undefined ? globalThis.caches : options.cacheStorage;
    cache = await storage.open(CACHE_NAME);
    const hit = await cache.match(url.href);
    if (hit) {
      return hit;
    }
  } catch {
    return fetchResponse(source);
  }

  const response = await fetchResponse(source);
  if (!response.ok || !response.body) {
    return response;
  }
  const total = decodedLength(response);
  if (total > MAX_CARTRIDGE_BYTES) {
    await response.body.cancel().catch(() => {});
    throw new Error("Invalid PNG cartridge size");
  }
  let received = 0;
  let transferError;
  const reader = response.body.getReader();
  let released = false;
  const cancelReader = async (reason) => {
    if (released) {
      return;
    }
    released = true;
    try {
      await reader.cancel(reason);
    } catch {
      // A failed network stream still needs its reader lock released.
    } finally {
      reader.releaseLock();
    }
  };
  // Own the source reader independently of CacheStorage's output reader.
  // This permits cancellation even if a failed put still holds its lock.
  const stream = new ReadableStream({
    async pull(controller) {
      try {
        const { value, done } = await reader.read();
        if (released) {
          return;
        }
        if (done) {
          if (!received || (total && received !== total)) {
            throw new Error("PNG cartridge length mismatch");
          }
          options.onProgress?.(received, received);
          released = true;
          reader.releaseLock();
          controller.close();
          return;
        }
        received += value.byteLength;
        if (received > MAX_CARTRIDGE_BYTES || (total && received > total)) {
          throw new Error("Invalid PNG cartridge size");
        }
        options.onProgress?.(received, total);
        controller.enqueue(value);
      } catch (error) {
        transferError = error;
        await cancelReader(error);
        controller.error(error);
      }
    },
    cancel: cancelReader,
  });
  try {
    await cache.put(
      url.href,
      new Response(stream, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      }),
    );
    const stored = await cache.match(url.href);
    if (stored) {
      // Only a successful replacement permits eviction. Keep the current
      // revision and one other entry; storage errors never prevent playing.
      try {
        const previous = (await cache.keys()).filter((request) => request.url !== url.href);
        for (const request of previous.slice(0, Math.max(0, previous.length - MAX_ENTRIES + 1))) {
          await cache.delete(request);
        }
      } catch {
        // Browser storage can become unavailable between operations.
      }
      const headers = new Headers(stored.headers);
      headers.delete("content-encoding");
      headers.set("content-length", String(received));
      return new Response(stored.body, {
        status: stored.status,
        statusText: stored.statusText,
        headers,
      });
    }
  } catch {
    await cancelReader();
    if (transferError) {
      throw transferError;
    }
  }
  // A failed cache write may have consumed part or all of its response.
  // Retry once without caching; an unavailable/quota-limited cache is optional.
  return fetchResponse(source);
}

export async function discardCachedCartridge(source) {
  const url = versionedUrl(source);
  if (!url) {
    return;
  }
  try {
    await (await globalThis.caches.open(CACHE_NAME)).delete(url.href);
  } catch {
    // Cleanup cannot replace the original loader error.
  }
}

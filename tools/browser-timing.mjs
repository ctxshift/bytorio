import { appendFileSync } from "node:fs";
import { chromium as playwrightChromium } from "playwright";

const methods = {
  browserType: { launch: "browser" },
  browser: { newPage: "page", newContext: "context", close: null },
  context: { newPage: "page", close: null },
  page: {
    goto: null,
    reload: null,
    setContent: null,
    evaluate: null,
    evaluateHandle: null,
    waitForFunction: null,
    waitForSelector: null,
    screenshot: null,
    close: null,
  },
};

// Observe public async operations without changing callbacks, arguments,
// timeouts or results. Internal Playwright calls retain their original receiver.
export function timeBrowser(browserType, record) {
  const objects = new WeakMap();
  let sequence = 0;
  function wrap(target, kind) {
    if (objects.has(target)) {
      return objects.get(target);
    }
    const id = `${kind}-${++sequence}`;
    const functions = new Map();
    const proxy = new Proxy(target, {
      get(object, property) {
        const value = Reflect.get(object, property, object);
        if (typeof value !== "function") {
          return value;
        }
        if (!functions.has(property)) {
          const measured = Object.hasOwn(methods[kind], property);
          functions.set(
            property,
            measured
              ? async (...args) => {
                  const startedAt = new Date().toISOString();
                  const started = performance.now();
                  const caller = new Error().stack
                    .split("\n")
                    .find((line) => line.includes(" at ") && !line.includes("browser-timing.mjs"))
                    ?.trim();
                  let error = null;
                  try {
                    const result = await value.apply(object, args);
                    return methods[kind][property] ? wrap(result, methods[kind][property]) : result;
                  } catch (caught) {
                    error = caught instanceof Error ? caught.message : String(caught);
                    throw caught;
                  } finally {
                    record({
                      pid: process.pid,
                      object: id,
                      phase: `${kind}.${property}`,
                      startedAt,
                      durationMs: performance.now() - started,
                      caller,
                      error,
                    });
                  }
                }
              : value.bind(object),
          );
        }
        return functions.get(property);
      },
    });
    objects.set(target, proxy);
    return proxy;
  }
  return wrap(browserType, "browserType");
}

const destination = process.env.VALIDATION_BROWSER_TIMINGS;
export const chromium = destination
  ? timeBrowser(playwrightChromium, (event) => {
      appendFileSync(destination, JSON.stringify(event) + "\n");
    })
  : playwrightChromium;

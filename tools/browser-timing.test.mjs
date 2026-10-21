import assert from "node:assert/strict";
import { test } from "node:test";
import { timeBrowser } from "./browser-timing.mjs";

test("browser timing preserves receivers, arguments, results and failures", async () => {
  const events = [];
  const failure = new Error("navigation failed");
  const page = {
    async evaluate(callback, input) {
      assert.equal(this, page);
      return callback(input);
    },
    async goto(url) {
      assert.equal(url, "failed://navigation");
      throw failure;
    },
    title() {
      assert.equal(this, page);
      return "fixture";
    },
  };
  const context = {
    async newPage() {
      return page;
    },
  };
  const browser = {
    async newContext() {
      return context;
    },
    async newPage() {
      return page;
    },
  };
  const type = {
    async launch(options) {
      assert.equal(this, type);
      assert.deepEqual(options, { headless: true });
      return browser;
    },
  };
  const observed = await timeBrowser(type, (event) => events.push(event)).launch({
    headless: true,
  });
  const observedPage = await (await observed.newContext()).newPage();
  assert.equal(await observed.newPage(), observedPage);
  const value = { value: 42 };
  assert.equal(await observedPage.evaluate((input) => input, value), value);
  assert.equal(observedPage.title(), "fixture");
  await assert.rejects(observedPage.goto("failed://navigation"), (error) => error === failure);
  assert.deepEqual(
    events.map(({ phase }) => phase),
    [
      "browserType.launch",
      "browser.newContext",
      "context.newPage",
      "browser.newPage",
      "page.evaluate",
      "page.goto",
    ],
  );
  assert.equal(events.at(-1).error, failure.message);
  assert.ok(events.slice(0, -1).every((event) => event.error === null));
  assert.ok(events.every((event) => event.durationMs >= 0 && event.startedAt && event.caller));
});

test("browser launch failures are timed and rethrown", async () => {
  const events = [];
  const failure = new Error("browser unavailable");
  const type = {
    async launch() {
      throw failure;
    },
  };
  await assert.rejects(
    timeBrowser(type, (event) => events.push(event)).launch(),
    (e) => e === failure,
  );
  assert.equal(events.length, 1);
  assert.equal(events[0].phase, "browserType.launch");
  assert.equal(events[0].error, failure.message);
});

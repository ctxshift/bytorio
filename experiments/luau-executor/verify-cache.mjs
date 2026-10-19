import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {serve} from '../../tools/serve.mjs';
const server=serve('build/unified-player/web',0);await once(server,'listening');
const browser=await chromium.launch({channel:process.env.PLAYER_BROWSER_CHANNEL||undefined});
try{
 const page=await browser.newPage();await page.goto(`http://127.0.0.1:${server.address().port}/comparison.html`);
 const first=await page.evaluate(async()=>{
  const {prepareExecutor}=await import('./executor-cache.js');
  const a=await prepareExecutor('./luau-executor.wasm'),b=await prepareExecutor('./luau-executor.wasm');
  return {a:a.cache,b:b.cache,same:a.module===b.module};
 });
 assert.equal(first.a.hit,false);assert.equal(first.b.hit,true);assert.equal(first.b.downloadedExecutor,false);assert.ok(first.same);
 const original=await readFile('build/unified-player/web/luau-executor.wasm');
 const changed=Buffer.concat([original,Buffer.from([0,1,0])]);
 const hash=createHash('sha256').update(changed).digest('hex');
 await page.route('**/executor-version.json',route=>route.fulfill({json:{sha256:hash}}));
 await page.route('**/luau-executor.wasm',route=>route.fulfill({body:changed,contentType:'application/wasm'}));
 const next=await page.evaluate(async()=>{
  const {prepareExecutor}=await import('./executor-cache.js');
  const a=await prepareExecutor('./luau-executor.wasm'),b=await prepareExecutor('./luau-executor.wasm');return {a:a.cache,b:b.cache};
 });
 assert.notEqual(next.a.key,first.a.key);assert.equal(next.a.hit,false);assert.equal(next.b.hit,true);
 await page.unroute('**/luau-executor.wasm');
 await page.route('**/executor-version.json',route=>route.fulfill({json:{sha256:'0'.repeat(64)}}));
 const mismatch=await page.evaluate(async()=>{try{const {prepareExecutor}=await import('./executor-cache.js');await prepareExecutor('./luau-executor.wasm');return '';}catch(error){return error.message;}});
 assert.match(mismatch,/version changed/,'stale or corrupt manifest cannot reuse old code');
 console.log('Browser compiled-module identity, no-download hit, version invalidation and hash-mismatch checks passed.');
}finally{await browser.close();await new Promise(resolve=>server.close(resolve));}

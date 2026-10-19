// PROTOTYPE: serial measurements of the same replay through the same player.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,stat} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {cpus,platform,arch,release} from 'node:os';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {serve} from '../../tools/serve.mjs';
import {loadSource,checkExecutor,uploadGraphics,submitDrawing,rasterizeDrawing} from '../../runtime/odin/web/policy.js';

const root='build/unified-player',out=`${root}/benchmark`;
await mkdir(out,{recursive:true});
const samples=Number(process.env.UNIFIED_BENCH_SAMPLES||5);
assert.ok(Number.isInteger(samples)&&samples>=1&&samples<=9);
const masks=[];
const tap=mask=>masks.push(mask,0),walk=(mask,n=1)=>{for(let i=0;i<n;i++)tap(mask);};
walk(4);walk(4);masks.push(16,...Array(12).fill(16),0);tap(16);walk(8);walk(2,9);walk(4);walk(2);walk(8);walk(2,5);
tap(16);tap(2);tap(16);tap(2);tap(16);tap(16);tap(1);tap(1);tap(16);tap(16);
tap(16);walk(2,4);tap(16);tap(16);walk(1,18);walk(4);tap(16);tap(16);tap(16);
assert.equal(masks.length,134);
await writeFile(`${out}/quest.inputs`,masks.join('\n')+'\n');
const defeat=[];
for(let i=0;i<14;i++)defeat.push(2,0);
defeat.push(2,0);for(let i=0;i<20;i++)defeat.push(16,0);defeat.push(16,0,4,0,16,0);
assert.equal(defeat.length,76);
await writeFile(`${out}/defeat.inputs`,defeat.join('\n')+'\n');
const imports={env:{sin:Math.sin}};
const wasm={odin:await readFile(`${root}/web/game.wasm`),luau:await readFile(`${root}/web/luau-executor.wasm`)};
const source=await readFile(`${root}/web/rpg.luau`),runtimeBytes=await readFile(`${root}/web/runtime.wasm`);
assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(wasm.luau)),[],'executor has no host imports');
for(const language of ['odin','luau'])assert.deepEqual(wasm[language],await readFile(`${root}/native/${language==='odin'?'game':'luau-executor'}.wasm`));

async function reference(language,inputs) {
    const game=(await WebAssembly.instantiate(wasm[language],imports)).instance.exports;
    const runtime=(await WebAssembly.instantiate(runtimeBytes,imports)).instance.exports;
    game._initialize?.();if(language==='luau')loadSource(game,source);
    game.game_init();checkExecutor(game);runtime.runtime_init();
    uploadGraphics(game,runtime);
    const frames=[];
    for(const mask of inputs) {
        game.game_update(mask,0,0,0);
        const drawing=submitDrawing(game,runtime),{record}=drawing;
        rasterizeDrawing(runtime,drawing);
        frames.push({hash:runtime.runtime_hash()>>>0,sounds:record.sounds});
    }
    if(language==='odin') {
        const state=new Int32Array(game.memory.buffer,game.game_inspect(),10);
        assert.equal(state[7],inputs===masks?15:1,'expected complete quest or recovered quest acceptance');
    }
    return frames;
}
const expected=await reference('odin',masks),defeatExpected=await reference('odin',defeat);
const golden=JSON.parse(await readFile('tests/rpg/parity.json','utf8'));
assert.deepEqual(expected,golden.quest,'batching preserves the original quest frames');
assert.deepEqual(defeatExpected,golden.defeat,'batching preserves the original defeat frames');
assert.deepEqual(await reference('luau',masks),expected);
assert.deepEqual(await reference('luau',defeat),defeatExpected);

function native(language,flags) {
    const args=['--game',`${root}/native/${language==='odin'?'game':'luau-executor'}.wasm`];
    if(language==='luau')args.push('--source',`${root}/native/rpg.luau`);
    const result=spawnSync(resolve(`${root}/native/player.exe`),[...args,...flags],{encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024});
    if(result.error)throw result.error;
    assert.equal(result.status,0,`${language}: ${result.stderr}`);
    return result.stdout;
}
for(const language of ['odin','luau']) {
    const lines=native(language,['--replay',`${out}/defeat.inputs`]).trim().split(/\r?\n/).map(line=>JSON.parse(line));
    assert.deepEqual(lines,defeatExpected,`${language} native defeat parity`);
    const env={...process.env,SDL_VIDEODRIVER:'dummy',SDL_AUDIODRIVER:'dummy',SDL_RENDER_DRIVER:'software'};
    const args=['--game',`${root}/native/${language==='odin'?'game':'luau-executor'}.wasm`,'--smoke','--capture',`${out}/${language}-native.bmp`];
    if(language==='luau')args.push('--source',`${root}/native/rpg.luau`);
    const smoke=spawnSync(resolve(`${root}/native/player.exe`),args,{env,encoding:'utf8',timeout:30000});
    assert.equal(smoke.status,0,smoke.stderr);
    const report=JSON.parse(smoke.stdout);
    assert.equal(report.ticks,120);assert.equal(report.hash,808241555);assert.ok(report.audioQueuedFrames>0);
}
console.log('Parity and native SDL checks passed for both cartridges.');
const nativeResults={metered:{odin:[],luau:[]},unmetered:{odin:[],luau:[]}};
for(const mode of ['metered','unmetered'])for(let i=0;i<samples;i++)for(const language of i%2?['luau','odin']:['odin','luau']) {
    const flags=['--benchmark',`${out}/quest.inputs`];
    if(mode==='unmetered')flags.push('--benchmark-unmetered');
    const report=JSON.parse(native(language,flags));
    assert.deepEqual(report.traces,expected,`${language} native ${mode} quest parity`);
    assert.equal(report.timings.length,masks.length*5);
    nativeResults[mode][language].push(report);
    console.log(`Native ${mode} ${language} sample ${i+1}/${samples}: ${report.startup.totalMs.toFixed(1)} ms startup.`);
}

const server=serve(`${root}/web`,0);await once(server,'listening');
let browser;
const browserResults={odin:[],luau:[]};
try {
    browser=await chromium.launch({channel:process.env.PLAYER_BROWSER_CHANNEL||undefined});
    const page=await browser.newPage({viewport:{width:1200,height:850}}),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    const base=`http://127.0.0.1:${server.address().port}`;
    for(const language of ['odin','luau']) {
        await page.goto(`${base}/player.html${language==='luau'?'?game=./rpg.luau':''}`);
        await page.waitForFunction(()=>playerStatus.ready||playerStatus.error);
        assert.equal(await page.evaluate(()=>playerStatus.error),'');
        await page.getByRole('button',{name:'Start game'}).click();
        const initial=await page.evaluate(()=>playerStatus.hash);
        await page.keyboard.down('ArrowUp');await page.waitForFunction(hash=>playerStatus.hash!==hash,initial);await page.keyboard.up('ArrowUp');
        await page.keyboard.down('Space');await page.waitForFunction(()=>playerStatus.sounds>=2);await page.keyboard.up('Space');
        assert.ok(await page.evaluate(()=>playerAudio.played>=2&&playerAudio.peak>0.1));
        await page.screenshot({path:`${out}/${language}-browser.png`});
    }
    await page.goto(`${base}/comparison.html`);
    for(let i=0;i<samples;i++)for(const language of i%2?['luau','odin']:['odin','luau']) {
        const result=await page.evaluate(async ({language,masks,defeat})=>{
            const started=performance.now(),worker=new Worker('./worker.js',{type:'module'});
            try {
                const exchange=data=>new Promise((resolve,reject)=>{
                    const timeout=setTimeout(()=>reject(new Error('Unified Worker benchmark timeout')),90000);
                    worker.onerror=event=>{clearTimeout(timeout);reject(new Error(event.message));};
                    worker.onmessage=({data})=>{if(data.type==='executing')return;clearTimeout(timeout);data.type==='error'?reject(new Error(data.error)):resolve(data);};
                    worker.postMessage(data);
                });
                const ready=await exchange({type:'load',gameUrl:language==='luau'?'./rpg.luau':'./game.wasm'});
                const workerReadyMs=performance.now()-started;
                const benchmark=await exchange({type:'benchmark',masks});
                // Restart the same instance, then check the separate defeat route.
                const recovered=await exchange({type:'benchmark',masks:defeat});
                return {...benchmark,workerReadyMs,initialMemory:ready.memory,defeatTraces:recovered.traces};
            }finally{worker.terminate();}
        },{language,masks,defeat});
        assert.deepEqual(result.traces,expected,`${language} browser quest parity`);
        assert.deepEqual(result.defeatTraces,defeatExpected,`${language} browser defeat parity`);
        browserResults[language].push(result);
        console.log(`Browser ${language} sample ${i+1}/${samples}: ${result.startup.totalMs.toFixed(1)} ms startup.`);
    }
    // Diagnostics must survive the C++ -> Wasm -> player boundary.
    const bad='return {init=function() error("prototype diagnostic") end, update=function() end, draw=function() end}';
    await writeFile(`${root}/web/diagnostic.luau`,bad);
    const failure=spawnSync(resolve(`${root}/native/player.exe`),['--game',`${root}/native/luau-executor.wasm`,'--source',`${root}/web/diagnostic.luau`,'--check'],{encoding:'utf8',timeout:10000});
    assert.equal(failure.status,1);assert.match(failure.stderr,/prototype diagnostic/);
    await page.goto(`${base}/player.html?game=./diagnostic.luau`);await page.waitForFunction(()=>!!playerStatus.error);
    assert.match(await page.evaluate(()=>playerStatus.error),/prototype diagnostic/);
    assert.deepEqual(errors,[]);
    const report={environment:{platform:platform(),arch:arch(),os:release(),cpu:cpus()[0].model,browser:browser.version(),samples,warmupPasses:2,measuredPasses:5,questTicks:134,defeatTicks:76},bytes:{odinModule:wasm.odin.length,luauExecutor:wasm.luau.length,luauCartridge:source.length,runtime:runtimeBytes.length,player:(await stat(`${root}/native/player.exe`)).size},native:nativeResults,browser:browserResults};
    await writeFile(`${out}/raw.json`,JSON.stringify(report)+'\n');
    const percentile=(values,p)=>{const sorted=[...values].sort((a,b)=>a-b);return sorted[Math.min(sorted.length-1,Math.ceil(sorted.length*p)-1)];};
    const summarize=reports=>{
        const rows=reports.flatMap(r=>r.timings),frames=rows.map(row=>row.slice(0,3).reduce((a,b)=>a+b,0));
        const mean=index=>rows.reduce((sum,row)=>sum+row[index],0)/rows.length;
        const median=fn=>percentile(reports.map(fn),0.5);
        return {startupMedianMs:median(r=>r.startup.totalMs),compileMedianMs:median(r=>r.startup.compileMs),gameInitMedianMs:median(r=>r.startup.gameInitMs),frameMeanMs:frames.reduce((a,b)=>a+b,0)/frames.length,frameP50Ms:percentile(frames,0.5),frameP95Ms:percentile(frames,0.95),updateMeanMs:mean(0),submitMeanMs:mean(1),renderMeanMs:mean(2),pixelCopyMeanMs:rows[0].length>3?mean(3):null,guestLinearBytes:median(r=>r.memory.currentLinear),heapPeakBytes:!reports[0].memory.heapBytes?null:Math.max(...reports.map(r=>r.memory.heapPeak)),workingSetMedianBytes:reports[0].memory.working?median(r=>r.memory.working):null,peakWorkingSetBytes:reports[0].memory.peakWorking?Math.max(...reports.map(r=>r.memory.peakWorking)):null,frameSamples:rows.length};
    };
    const summary={environment:report.environment,bytes:report.bytes,native:{metered:{},unmetered:{}},browser:{}};
    for(const mode of ['metered','unmetered'])for(const language of ['odin','luau'])summary.native[mode][language]=summarize(nativeResults[mode][language]);
    for(const language of ['odin','luau'])summary.browser[language]=summarize(browserResults[language]);
    await writeFile(`${out}/summary.json`,JSON.stringify(summary,null,2)+'\n');
    console.log(JSON.stringify(summary,null,2));
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}

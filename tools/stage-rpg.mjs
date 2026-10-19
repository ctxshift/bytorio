import { readFile, writeFile, copyFile, mkdir, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
const destination=process.argv[2]||'build/rpg/site';
await mkdir(destination,{recursive:true});
await copyFile('examples/rpg-shared/launcher.html',`${destination}/player.html`);
for(const language of ['odin','luau']) {
    const source=`build/rpg-${language}/web`, target=`${destination}/${language}`;
    await mkdir(`${target}/licenses`,{recursive:true});
    const names=language==='odin'?['player.js','worker.js','policy.js','runtime.wasm','game.wasm']:['player.js','player.wasm','player.data'];
    for(const name of names)await copyFile(`${source}/${name}`,`${target}/${name}`);
    for(const name of await readdir(`${source}/licenses`))await copyFile(`${source}/licenses/${name}`,`${target}/licenses/${name}`);
    const html=await readFile(`${source}/player.html`,'utf8');
    await writeFile(`${target}/player.html`,html.replace('</body>','<script type="module" src="./controls.js"></script>\n</body>'));
    await copyFile('examples/rpg-shared/controls.js',`${target}/controls.js`);
}
console.log(`RPG comparison site ready at ${resolve(destination)}.`);

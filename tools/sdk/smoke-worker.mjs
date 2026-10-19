import {parentPort,workerData} from 'node:worker_threads';
import {readFile} from 'node:fs/promises';
import {inspectGuest,loadSource,checkExecutor,uploadGraphics,submitDrawing,rasterizeDrawing} from '../../runtime/odin/web/policy.js';
try {
  const imports={env:{sin:Math.sin}};
  const bytes=await readFile(workerData.game);inspectGuest(bytes);
  const game=(await WebAssembly.instantiate(bytes,imports)).instance.exports;
  const runtime=(await WebAssembly.instantiate(await readFile(workerData.runtime),imports)).instance.exports;
  const source=workerData.source?await readFile(workerData.source):null;
  parentPort.postMessage({type:'executing'});
  game._initialize?.();if(source)loadSource(game,source);
  if(game.game_abi()!==1||game.game_sdk_version()!==256||game.game_command_stride()!==32)throw new Error('Unsupported SDK/ABI version');
  game.game_init();checkExecutor(game);runtime.runtime_init();uploadGraphics(game,runtime);
  for(let i=0;i<3;i++){game.game_update(0,0,0,0);const drawing=submitDrawing(game,runtime);rasterizeDrawing(runtime,drawing);}
  parentPort.postMessage({type:'checked'});
}catch(error){parentPort.postMessage({type:'error',message:error.message});}

import {resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {watch} from 'node:fs';
import {createProject,checkProject,buildProject} from './sdk/project.mjs';
import {serve} from './serve.mjs';

const [action,path,...args]=process.argv.slice(2);
const help='Usage: node tools/console.mjs new <directory> [--language luau|odin]\n       node tools/console.mjs check|build <directory>\n       node tools/console.mjs run|watch <directory> [--web|--native] [--port 8080]';
try {
 if(action==='--help'||action==='help'||!action){console.log(help);}
 else {
  if(!path)throw new Error(help);
  const options={};
  for(let i=0;i<args.length;i++) {
   if(args[i]==='--language'||args[i]==='--port'){if(!args[i+1])throw new Error('Missing option value');options[args[i].slice(2)]=args[++i];}
   else if(['--web','--native'].includes(args[i]))options[args[i].slice(2)]=true;
   else throw new Error(`Unknown option: ${args[i]}`);
  }
  if(options.web&&options.native)throw new Error('Choose --web or --native');
  if(action==='new')await createProject(path,options.language||'luau');
  else if(action==='check')await checkProject(path);
  else if(action==='build')await buildProject(path);
  else if(action==='run'||action==='watch') {
   let spec=await buildProject(path),child;
   const launch=()=>{
    const base=resolve(spec.project,'build/native');
    const flags=spec.language==='luau'?['--game',resolve(base,'luau-executor.wasm'),'--source',resolve(base,'game.luau')]:[];
    child=spawn(resolve(base,'player.exe'),flags,{stdio:'inherit'});
    child.on('error',error=>console.error(error.message));
   };
   if(options.native)launch();
   else {
    const port=Number(options.port||8080);if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Invalid port');
    const server=serve(resolve(spec.project,'build/web'),port);
    server.on('error',error=>{console.error(error.message);process.exitCode=1;});
    server.on('listening',()=>console.log(`Player: http://127.0.0.1:${port}/player.html`));
   }
   if(action==='watch') {
    let pending=false,dirty=false,timer;
    const rebuild=async()=>{
     if(pending){dirty=true;return;}pending=true;
     try {
      if(options.native&&child&&child.exitCode===null){await new Promise(resolve=>{child.once('exit',resolve);child.kill();});}
      spec=await buildProject(path);
      if(options.native)launch();else console.log('Build ready. Reload the browser to start fresh.');
     }
     catch(error){console.error(error.message);}finally{pending=false;if(dirty){dirty=false;timer=setTimeout(rebuild,150);}}
    };
    watch(spec.project,{recursive:true},(_event,file)=>{
     const name=String(file).replaceAll('\\','/');
     if(name.startsWith('build/')||name.startsWith('.console/')||name.startsWith('.git/'))return;
     if(!/\.(odin|luau|json)$/.test(name))return;
     clearTimeout(timer);timer=setTimeout(rebuild,150);
    });
    console.log('Watching source and assets. Ctrl+C to stop.');
   }
  } else throw new Error(help);
 }
}catch(error){console.error(error.message);process.exitCode=1;}

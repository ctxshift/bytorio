import {compileExecutor,cachedExecutor} from './executor-cache-core.js';
export async function prepareExecutor(url,{bypass=false}={}) {
  const started=performance.now(),absolute=new URL(url,location.href);
  let expectedHash=null;
  if(absolute.protocol==='http:'||absolute.protocol==='https:') {
    const version=await fetch(new URL('./executor-version.json',absolute),{cache:'no-cache'});
    if(!version.ok)throw new Error('Could not load the executor version.');
    expectedHash=(await version.json()).sha256;
    if(!/^[a-f0-9]{64}$/.test(expectedHash))throw new Error('Invalid executor version.');
    if(!bypass){
      const cached=await cachedExecutor(expectedHash);
      if(cached)return {...cached,cache:{...cached.cache,scope:'page',fetchMs:performance.now()-started,prepareMs:performance.now()-started,downloadedExecutor:false}};
    }
  }
  const response=await fetch(absolute,{cache:'no-cache'});
  if(!response.ok)throw new Error('Could not load the Luau executor.');
  const bytes=await response.arrayBuffer(),fetchMs=performance.now()-started;
  const result=await compileExecutor(bytes,bypass,expectedHash);
  return {module:result.module,bytes,cache:{...result.cache,scope:'page',fetchMs,prepareMs:performance.now()-started,downloadedExecutor:true}};
}

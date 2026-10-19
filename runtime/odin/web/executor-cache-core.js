// Cache code only; each cartridge still gets a new instance and linear memory.
const entries=new Map();
export async function cachedExecutor(hash) {
  const key='executor-v1:'+hash,entry=entries.get(key);
  if(!entry)return null;
  const module=await entry.pending;
  return {module,bytes:entry.bytes.slice(0),cache:{enabled:true,hit:true,key,lookupMs:0,compileMs:0}};
}
export async function compileExecutor(bytes,bypass=false,expectedHash=null) {
  if(!(bytes instanceof ArrayBuffer)||bytes.byteLength>1024*1024)throw new Error('Invalid executor module size.');
  const started=performance.now();
  const hash=await crypto.subtle.digest('SHA-256',bytes);
  const key='executor-v1:'+Array.from(new Uint8Array(hash),n=>n.toString(16).padStart(2,'0')).join('');
  if(expectedHash&&key!=='executor-v1:'+expectedHash)throw new Error('Executor version changed during loading. Reload to retry.');
  let pending=bypass?undefined:entries.get(key)?.pending;
  const hit=!!pending,lookupMs=performance.now()-started;
  const compileStarted=performance.now();
  if(!pending){
    pending=WebAssembly.compile(bytes);
    if(!bypass){
      entries.set(key,{pending,bytes:bytes.slice(0)});
      while(entries.size>4)entries.delete(entries.keys().next().value);
    }
  }
  try {
    const module=await pending;
    return {module,cache:{enabled:!bypass,hit,key,lookupMs,compileMs:hit?0:performance.now()-compileStarted}};
  }catch(error){if(entries.get(key)?.pending===pending)entries.delete(key);throw error;}
}

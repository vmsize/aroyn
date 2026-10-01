import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const folder=path.dirname(fileURLToPath(import.meta.url));
for(const suite of ['web-check','check','security-check','data-check','snapshot-race-check','access-check','hibernation-check','retention-check','recovery-check','mutation-race-check']) {
  console.log(`\nRunning ${suite}`);
  const status=await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[path.join(folder,suite+'.mjs')],{stdio:'inherit'});
    child.on('error',reject);child.on('exit',resolve);
  });
  if(status!==0)process.exit(status||1);
}

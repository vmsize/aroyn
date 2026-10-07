import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const folder=path.dirname(fileURLToPath(import.meta.url));
for(const suite of ['pet-feed-check','executor-metadata-check','client-presence-websocket-check','presence-websocket-check','client-presence-check','presence-accounting-check','client-updates-check','market-cancellation-check','compost-cancellation-check','compost-prompt-cancellation-check','neighbor-cancellation-check','auth-ui-race-check','auth-storage-check','account-key-cleanup-check','runtime-stream-recovery-check','live-snapshot-fragments-check','web-check','accessibility-ui-check','deployment-config-check','dashboard-stability-check','check','security-check','data-check','snapshot-race-check','access-check','hibernation-check','retention-check','recovery-check','mutation-race-check','deletion-ledger-check','ledger-cutover-check','write-budget-check','usage-report-check','p1-regression-check','auth-revocation-check','analytics-deletion-check']) {
  console.log(`\nRunning ${suite}`);
  const status=await new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[path.join(folder,suite+'.mjs')],{stdio:'inherit'});
    child.on('error',reject);child.on('exit',resolve);
  });
  if(status!==0)process.exit(status||1);
}

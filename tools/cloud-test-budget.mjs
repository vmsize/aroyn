import fs from 'node:fs/promises';
import path from 'node:path';

// Operator preflight, not a provider-wide spending cap. Cloud metrics can lag
// and other applications can spend quota after capture. Never use for live auth.
export const CLOUD_TEST_LIMITS = Object.freeze({dailyRowWrites:100000, reserve:30000, perRun:1000, dailyFixtures:2000, metricsMaxAgeMs:300000});
export function assertCloudTestBudget(report, estimatedRowWrites, now=Date.now()) {
 const l=CLOUD_TEST_LIMITS, day=new Date(now).toISOString().slice(0,10);
 if(!Number.isSafeInteger(now)||now<=0||report?.format!=='aroyn-d1-budget-v1'||report.complete!==true||typeof report.accountId!=='string'||!/^[a-f0-9]{32}$/.test(report.accountId))throw new Error('Complete account usage report required');
 if(report.date!==day||!Number.isSafeInteger(report.collectedAt)||report.collectedAt>now||now-report.collectedAt>l.metricsMaxAgeMs)throw new Error('Fresh same-day account metrics required');
 if(!Number.isSafeInteger(report.rowsWritten)||report.rowsWritten<0)throw new Error('Invalid account write count');
 if(!Number.isSafeInteger(estimatedRowWrites)||estimatedRowWrites<1||estimatedRowWrites>l.perRun)throw new Error('Cloud test too large; run capacity checks locally');
 if(report.rowsWritten+estimatedRowWrites>l.dailyRowWrites-l.reserve)throw new Error('Insufficient account quota headroom; cloud writes blocked');
 return {accountId:report.accountId,date:day,estimatedRowWrites};
}

// Shared per-account reservation file across all disposable test harnesses.
// Reserve the worst-case writes, including setup/indexes/deletion/cleanup, even
// when the run later fails. A failed reservation never grants permission.
export async function reserveCloudTestBudget({metricsPath,reservationsPath,estimatedRowWrites,now=Date.now()}) {
 if(!metricsPath||!reservationsPath||!path.isAbsolute(metricsPath)||!path.isAbsolute(reservationsPath))throw new Error('Explicit absolute operator budget files required');
 const report=JSON.parse(await fs.readFile(metricsPath,'utf8'));
 const request=assertCloudTestBudget(report,estimatedRowWrites,now);
 await fs.mkdir(path.dirname(reservationsPath),{recursive:true});
 const lock=await fs.open(reservationsPath+'.lock','wx');
 try {
  let previous;
  try {previous=JSON.parse(await fs.readFile(reservationsPath,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
  if(previous&&(previous.accountId!==request.accountId||!Number.isSafeInteger(previous.reserved)||previous.reserved<0||!/^\d{4}-\d{2}-\d{2}$/.test(previous.date)||previous.date>request.date))throw new Error('Invalid reservation ledger');
  const used=previous?.date===request.date?previous.reserved:0;
  if(used+estimatedRowWrites>CLOUD_TEST_LIMITS.dailyFixtures)throw new Error('Daily cloud fixture allowance exhausted');
  const next={accountId:request.accountId,date:request.date,reserved:used+estimatedRowWrites};
  await fs.writeFile(reservationsPath,JSON.stringify(next)+'\n');
  return request;
 } finally {await lock.close();await fs.unlink(reservationsPath+'.lock');}
}

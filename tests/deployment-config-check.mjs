import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { deploymentConfig, prepareDashboard } from '../tools/prepare-dashboard.mjs';
const checks=[];async function check(name,fn){await fn();checks.push(name);}
const endpoints={apiBase:'https://api.example.test',liveBase:'https://live.example.test',scriptLoaderUrl:'https://site.example.test/scripts/loader.luau'};
await check('cloud preparation rejects local and unsafe Worker endpoints',()=>{
 for(const apiBase of ['http://127.0.0.1:8787','https://127.0.0.1','https://localhost','https://x.localhost','https://[::1]','https://10.0.0.1','http://api.example.test','https://user:secret@api.example.test','https://api.example.test/?x=1','https://api.example.test/#x','https://api.example.test/path'])assert.throws(()=>deploymentConfig({...endpoints,apiBase}));
 for(const liveBase of ['', 'ws://live.example.test','http://127.0.0.1:8788'])assert.throws(()=>deploymentConfig({...endpoints,liveBase}));
});
await check('cloud config sets HTTPS API and live plus the matching WSS endpoint',()=>{
 const ctx=vm.createContext({});vm.runInContext(deploymentConfig(endpoints).replaceAll('export const ','globalThis.'),ctx);
 assert.equal(ctx.API_BASE,endpoints.apiBase);assert.equal(ctx.LIVE_BASE,endpoints.liveBase);assert.equal(ctx.LIVE_WS_BASE,'wss://live.example.test/ws');assert.equal(ctx.SCRIPT_LOADER_URL,endpoints.scriptLoaderUrl);
});
await check('actual auth service sends login to configured cloud API',async()=>{
 const source=(await fs.readFile(new URL('../apps/dashboard/assets/js/services/auth-service.js',import.meta.url),'utf8')).replace(/^import .*;\r?\n/gm,'').replace('export const authService=', 'globalThis.authService=').replace(/^export \{.*;\r?$/gm,'');
 const ctx=vm.createContext({API_BASE:endpoints.apiBase,storage:{getRaw:(key,fallback)=>fallback},window:{addEventListener(){}},location:{pathname:'/dashboard/',search:'',href:'https://site.example.test/dashboard/'}});
 vm.runInContext(source,ctx);ctx.authService.login('/dashboard/');const url=new URL(ctx.location.href);
 assert.equal(url.origin,endpoints.apiBase);assert.equal(url.pathname,'/api/v2/auth/discord/start');assert.equal(url.searchParams.get('returnTo'),'/dashboard/');
});
await check('preparing the actual dashboard retains release assets and replaces local defaults',async()=>{
 const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-pages-'));const output=path.join(temp,'site');
 const result=await prepareDashboard({source:new URL('../apps/dashboard/',import.meta.url).pathname.replace(/^\/(\w:)/,'$1'),output,...endpoints,restrictedStaging:true});
 assert(result.files>50);assert.equal(await fs.readFile(path.join(output,'assets/js/core/config.js'),'utf8'),deploymentConfig(endpoints));
 assert((await fs.readFile(path.join(output,'_headers'),'utf8')).includes('noindex, nofollow'));
 for(const file of ['package.json','scripts/dev-server.mjs'])await assert.rejects(fs.access(path.join(output,file)));
 const original=await fs.readFile(new URL('../apps/dashboard/releases/4.3.80/greedy-growers.luau',import.meta.url));assert((await fs.readFile(path.join(output,'releases/4.3.80/greedy-growers.luau'))).equals(original));
 await assert.rejects(prepareDashboard({source:new URL('../apps/dashboard/',import.meta.url).pathname.replace(/^\/(\w:)/,'$1'),output,...endpoints}),/must be empty/);
 // Temp fixtures are small; kept for this process, no destructive recursive cleanup.
});
await fs.writeFile(new URL('deployment-config-results.json',import.meta.url),JSON.stringify({date:'2026-10-02',passed:checks.length,checks},null,2)+'\n');console.log(JSON.stringify({passed:checks.length,checks}));

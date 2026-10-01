import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {launchCommand, mountScriptLaunch} from '../apps/dashboard/assets/js/components/script-launch.js';
import {checkHealth} from '../apps/dashboard/assets/js/services/service-health.js';
import {safeAvatarUrl, safeScriptBloxUrl} from '../apps/dashboard/assets/js/utils/owner-urls.js';
const base=path.dirname(fileURLToPath(import.meta.url));
const checks=[];
async function check(name,fn){await fn();checks.push(name);}
await check('launch command rejects credentials, invalid schemes and URL payloads',()=>{
  for(const value of ['', 'not a URL','http://example.org/loader.luau','https://user:secret@example.org/loader.luau','https://example.org/loader.luau?key=secret','https://example.org/loader.luau#secret','https://example.org/script.js'])assert.equal(launchCommand(value),'');
  assert.equal(launchCommand('https://aroyn-staging.pages.dev/scripts/loader.luau'),'loadstring(game:HttpGet("https://aroyn-staging.pages.dev/scripts/loader.luau"))()');
});
function fixture(){
 const nodes={button:{disabled:false,addEventListener(type,fn){this.click=fn;}},status:{textContent:'',classList:{add(){},remove(){}}},field:{value:'',focus(){this.focused=true},select(){this.selected=true}},manual:{hidden:true}};
 const root={hidden:true,querySelector(selector){return({'[data-copy-script]':nodes.button,'[data-copy-status]':nodes.status,'[data-launch-command]':nodes.field,'[data-manual-copy]':nodes.manual})[selector];}};
 return {root,...nodes};
}
await check('clipboard success copies exact command and announces result',async()=>{
 const f=fixture();let copied='';mountScriptLaunch(f.root,'https://aroyn-staging.pages.dev/scripts/loader.luau',{writeText:async text=>{copied=text}});await f.button.click();assert.equal(copied,f.field.value);assert.equal(f.status.textContent,'Script copied');assert.equal(f.button.disabled,false);
});
await check('clipboard denial exposes focused selected manual command',async()=>{
 const f=fixture();mountScriptLaunch(f.root,'https://aroyn-staging.pages.dev/scripts/loader.luau',{writeText:async()=>{throw new Error('denied')}});await f.button.click();assert.ok(!f.manual.hidden&&f.field.focused&&f.field.selected);assert.match(f.status.textContent,/manually/);
});
await check('unpublished loader stays hidden',()=>{const f=fixture();mountScriptLaunch(f.root,'');assert.equal(f.root.hidden,true);assert.equal(f.button.click,undefined);});
await check('health sends no credentials and accepts only explicit ok true',async()=>{
 let options;const yes=await checkHealth('https://example.org/health',{fetcher:async(url,opts)=>{options=opts;return new Response('{"ok":true}')}});assert.ok(yes.responding);assert.equal(options.credentials,'omit');assert.equal(options.cache,'no-store');assert.equal(options.headers.Authorization,undefined);
 for(const body of ['{}','{"ok":"true"}','<html>error</html>'])assert.equal((await checkHealth('https://example.org/health',{fetcher:async()=>new Response(body)})).responding,false);
 assert.equal((await checkHealth('https://example.org/health',{fetcher:async()=>new Response('{"ok":true}',{status:503})})).responding,false);
});
await check('health has a bounded timeout',async()=>{
 const result=await checkHealth('https://example.org/health',{timeoutMs:5,fetcher:async(url,{signal})=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new Error('aborted'))))});assert.equal(result.reason,'Timed out');
});
await check('external owner images and links reject untrusted URLs',()=>{
 for(const u of ['https://rbxcdn.com.evil.test/a.png','https://user:pass@rbxcdn.com/a.png','http://t.rbxcdn.com/a.png','javascript:alert(1)'])assert.equal(safeAvatarUrl(u),'/assets/aroyn-mark.png');assert.equal(safeAvatarUrl('https://tr.rbxcdn.com/a.png'),'https://tr.rbxcdn.com/a.png');
 for(const u of ['javascript:alert(1)','https://scriptblox.com.evil.test/script/x','https://scriptblox.com/account','https://user:pass@scriptblox.com/script/x'])assert.equal(safeScriptBloxUrl(u),'');assert.equal(safeScriptBloxUrl('https://scriptblox.com/script/example'),'https://scriptblox.com/script/example');
});
const storageSource=await fs.readFile(path.join(base,'../apps/dashboard/assets/js/core/storage.js'),'utf8');
function storageFixture(initial={},throwOnWrite=false){
 const values=new Map(Object.entries(initial));const sandbox={localStorage:{getItem:k=>values.get(k)??null,setItem(k,v){if(throwOnWrite)throw new Error('quota');values.set(k,v)},removeItem:k=>values.delete(k)}};
 vm.runInNewContext(storageSource.replace('export const storage=', 'this.storage='),sandbox);return {storage:sandbox.storage,values};
}
await check('migration preserves legacy settings and explicit new empty session',()=>{
 const f=storageFixture({'veyra.theme.mode':'light','veyra.auth.session':'old-fixture','aroyn.auth.session':''});assert.equal(f.storage.getRaw('theme.mode','dark'),'light');assert.equal(f.values.get('aroyn.theme.mode'),'light');assert.equal(f.storage.getRaw('auth.session','x'),'');
 assert.equal(storageFixture({'veyra.theme.mode':'light'},true).storage.getRaw('theme.mode','dark'),'light');
});
await check('signout reaches old tabs and reset cannot resurrect legacy data',()=>{
 const f=storageFixture({'veyra.runtime.config':'{"x":1}','aroyn.auth.session':'fixture','veyra.auth.session':'fixture'});f.storage.setRaw('auth.session','');assert.equal(f.values.get('aroyn.auth.session'),'');assert.equal(f.values.get('veyra.auth.session'),'');f.storage.remove('runtime.config');assert.equal(f.storage.get('runtime.config',null),null);
});
await check('all javascript parses',async()=>{
 const {spawnSync}=await import('node:child_process');
 async function files(dir){let out=[];for(const e of await fs.readdir(dir,{withFileTypes:true})){const p=path.join(dir,e.name);out.push(...(e.isDirectory()?await files(p):p.endsWith('.js')?[p]:[]));}return out;}
 for(const file of await files(path.join(base,'../apps/dashboard/assets/js'))){const result=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});assert.equal(result.status,0,`${path.basename(file)}: ${result.stderr}`);}
});
await fs.writeFile(path.join(base,'web-check-results.json'),JSON.stringify({date:'2026-10-01',passed:checks.length,checks,browserCheckedSeparately:true},null,2)+'\n');
console.log(JSON.stringify({passed:checks.length,checks}));

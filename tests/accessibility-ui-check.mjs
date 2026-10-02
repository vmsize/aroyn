import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';
const checks=[];async function check(name,fn){await fn();checks.push(name);}
const helper=await fs.readFile(new URL('../apps/dashboard/assets/js/core/disclosure.js',import.meta.url),'utf8');
const load=async name=>(await fs.readFile(new URL(`../apps/dashboard/assets/js/components/${name}.js`,import.meta.url),'utf8')).replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,'');
async function fixture(names=['roblox-account-selector']){
 const {document,window,HTMLElement}=parseHTML('<html data-theme="dark"><body><div class="header-actions"><button data-settings-trigger>Settings</button></div><button id="outside">Outside</button></body></html>');
 let active=document.body;Object.defineProperty(document,'activeElement',{get:()=>active?.isConnected?active:document.body});
 // Model focus targets and events; this is not a browser tab-order or AT simulation.
 HTMLElement.prototype.focus=function(){if(this.closest('[inert]')||this.disabled)return;active=this;this.dispatchEvent(new window.Event('focusin',{bubbles:true}));};
 const accounts=[{userId:'101',username:'alpha',displayName:'Alpha',online:true},{userId:'202',username:'beta',displayName:'Beta',online:false}];
 const runtime={bridge:{accounts,accountsLoaded:true,selectedRobloxUserId:'202'}};const runtimeListeners=new Set(),authListeners=new Set(),selected=[];
 const auth={status:'authenticated',user:{id:'synthetic-owner',username:'owner',displayName:'Owner',dashboardKey:{exists:true,suffix:'fixture'}}};
 const calls={keys:0,remove:0};const runtimeService={getSnapshot:()=>runtime,subscribe(fn){runtimeListeners.add(fn);return()=>runtimeListeners.delete(fn)},async selectRobloxAccount(id){selected.push(id);runtime.bridge.selectedRobloxUserId=id;for(const fn of runtimeListeners)fn(runtime);return true},async removeRobloxAccount(){calls.remove++;return true}};
 const authService={getSnapshot:()=>auth,subscribe(fn){authListeners.add(fn)},init:async()=>auth,async generateDashboardKey(){calls.keys++;return{dashboardKey:'synthetic-key'}},async logout(){},login(){}};
 const ctx=vm.createContext({document,window,console,location:{pathname:'/dashboard/',search:''},navigator:{clipboard:{writeText:async()=>{}}},toast(){},runtimeService,authService,icons:{sun:'sun',moon:'moon'},getTheme:()=>({mode:'dark',accent:'steel'}),applyTheme(){},toggleThemeAnimated:async()=>{}});
 vm.runInContext(helper.replace(/^export /gm,''),ctx);
 for(const name of names){const source=await load(name);const fn={'roblox-account-selector':'mountRobloxAccountSelector',settings:'mountSettings',account:'mountAccount'}[name];vm.runInContext(`(()=>{${source};globalThis.${fn}=${fn}})()`,ctx);ctx[fn]();}
 const click=node=>node.dispatchEvent(new window.Event('click',{bubbles:true,cancelable:true}));
 const key=(node,key)=>{const e=new window.Event('keydown',{bubbles:true,cancelable:true});Object.defineProperty(e,'key',{value:key});node.dispatchEvent(e);return e;};
 const emitRuntime=()=>{for(const fn of runtimeListeners)fn(runtime)};const emitAuth=()=>{for(const fn of authListeners)fn(auth)};
 return{document,window,ctx,runtime,auth,calls,selected,click,key,emitRuntime,emitAuth};
}
async function settle(){for(let i=0;i<15;i++)await Promise.resolve();}
await check('selector starts closed, inert and excluded from accessibility tree',async()=>{
 const f=await fixture();const menu=f.document.querySelector('[data-roblox-account-menu]'),trigger=f.document.querySelector('[data-roblox-account-trigger]');
 assert(menu.hasAttribute('inert'));assert.equal(menu.getAttribute('aria-hidden'),'true');assert.equal(trigger.getAttribute('aria-haspopup'),'dialog');assert.equal(trigger.getAttribute('aria-controls'),menu.id);
 const options=[...menu.querySelectorAll('[data-roblox-user-id]')];assert.equal(options.length,2);assert(options.every(x=>x.tagName==='BUTTON'&&x.getAttribute('type')==='button'));assert.equal(menu.querySelector('[role="option"]'),null);assert.equal(menu.querySelector('button button'),null);
});
await check('opening moves focus to selected account; arrows Home and End move among choices',async()=>{
 const f=await fixture();const trigger=f.document.querySelector('[data-roblox-account-trigger]'),menu=f.document.querySelector('[data-roblox-account-menu]');trigger.focus();f.key(trigger,'ArrowDown');
 assert.equal(menu.getAttribute('aria-hidden'),'false');assert(!menu.hasAttribute('inert'));assert.equal(f.document.activeElement.dataset.robloxUserId,'202');
 f.key(f.document.activeElement,'ArrowDown');assert.equal(f.document.activeElement.dataset.robloxUserId,'101');f.key(f.document.activeElement,'End');assert.equal(f.document.activeElement.dataset.robloxUserId,'202');f.key(f.document.activeElement,'Home');assert.equal(f.document.activeElement.dataset.robloxUserId,'101');
});
await check('native selection click changes account and closes with trigger focus',async()=>{
 const f=await fixture();const trigger=f.document.querySelector('[data-roblox-account-trigger]');f.click(trigger);const choice=f.document.querySelector('[data-roblox-user-id="101"]');choice.focus();f.click(choice);await settle();
 assert.deepEqual(f.selected,['101']);assert.equal(f.document.activeElement,trigger);assert.equal(trigger.getAttribute('aria-expanded'),'false');assert(f.document.querySelector('[data-roblox-account-menu]').hasAttribute('inert'));
});
await check('Escape closes panel and returns focus, Tab-away focus closes without stealing it',async()=>{
 const f=await fixture();const trigger=f.document.querySelector('[data-roblox-account-trigger]'),menu=f.document.querySelector('[data-roblox-account-menu]');f.click(trigger);assert(f.key(f.document.activeElement,'Escape').defaultPrevented);assert.equal(f.document.activeElement,trigger);assert(menu.hasAttribute('inert'));
 f.click(trigger);const outside=f.document.querySelector('#outside');outside.focus();assert.equal(f.document.activeElement,outside);assert(menu.hasAttribute('inert'));
});
await check('telemetry refresh preserves focused choice after account markup changes',async()=>{
 const f=await fixture();f.click(f.document.querySelector('[data-roblox-account-trigger]'));f.document.querySelector('[data-roblox-user-id="101"]').focus();f.runtime.bridge.accounts[0].online=false;f.emitRuntime();
 assert.equal(f.document.activeElement.dataset.robloxUserId,'101');assert(f.document.activeElement.isConnected);assert.equal(f.document.querySelector('[data-roblox-account-menu]').dataset.open,'true');
});
await check('remove confirmation defaults focus to Cancel and does not select or remove account',async()=>{
 const f=await fixture();f.click(f.document.querySelector('[data-roblox-account-trigger]'));const remove=f.document.querySelector('[data-remove-roblox-user-id="101"]');remove.focus();f.click(remove);await settle();
 assert(f.document.activeElement.hasAttribute('data-remove-cancel'));assert.equal(f.calls.remove,0);assert.equal(f.selected.length,0);f.click(f.document.activeElement);assert.equal(f.document.activeElement.dataset.removeRobloxUserId,'101');assert.equal(f.document.querySelector('[data-remove-confirm]'),null);
});
await check('empty account list opens a labelled panel and Escape still works',async()=>{
 const f=await fixture();f.runtime.bridge.accounts=[];f.emitRuntime();const trigger=f.document.querySelector('[data-roblox-account-trigger]');f.click(trigger);assert.equal(f.document.activeElement,f.document.querySelector('[data-roblox-account-menu]'));f.key(f.document.activeElement,'Escape');assert.equal(f.document.activeElement,trigger);
});
await check('settings and account panels start inert and focus inside only while open',async()=>{
 const f=await fixture(['settings','account']);const settings=f.document.querySelector('.settings-panel'),account=f.document.querySelector('.account-panel');assert(settings.hasAttribute('inert'));assert(account.hasAttribute('inert'));
 f.click(f.document.querySelector('[data-settings-trigger]'));assert(settings.contains(f.document.activeElement));f.key(f.document.activeElement,'Escape');assert(settings.hasAttribute('inert'));assert.equal(f.document.activeElement,f.document.querySelector('[data-settings-trigger]'));
 f.click(f.document.querySelector('[data-account-trigger]'));assert(account.contains(f.document.activeElement));f.key(f.document.activeElement,'Escape');assert(account.hasAttribute('inert'));assert.equal(f.document.activeElement,f.document.querySelector('[data-account-trigger]'));
});
await check('opening another disclosure closes the previous panel',async()=>{
 const f=await fixture(['settings','account','roblox-account-selector']);f.click(f.document.querySelector('[data-settings-trigger]'));f.click(f.document.querySelector('[data-roblox-account-trigger]'));
 assert(f.document.querySelector('.settings-panel').hasAttribute('inert'));assert(!f.document.querySelector('[data-roblox-account-menu]').hasAttribute('inert'));
});
await check('account refresh preserves focused action; replacement focuses safe Cancel',async()=>{
 const f=await fixture(['account']);f.click(f.document.querySelector('[data-account-trigger]'));f.document.querySelector('[data-account-data]').focus();f.auth.user.displayName='Updated';f.emitAuth();assert(f.document.activeElement.hasAttribute('data-account-data'));
 f.click(f.document.querySelector('[data-key-generate]'));await settle();assert(f.document.activeElement.hasAttribute('data-key-cancel'));assert.equal(f.calls.keys,0);f.key(f.document.activeElement,'Escape');assert(f.document.querySelector('.account-panel').hasAttribute('inert'));f.click(f.document.querySelector('[data-account-trigger]'));assert.equal(f.document.querySelector('[data-key-cancel]'),null);
});
function luminance(hex){const rgb=hex.replace('#','').match(/../g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;}
function ratio(a,b){const x=luminance(a),y=luminance(b);return(Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
await check('all log level ink meets 4.5 contrast against normal and hovered backgrounds in both themes',async()=>{
 const css=await fs.readFile(new URL('../apps/dashboard/assets/styles/tokens.css',import.meta.url),'utf8');const dashboard=await fs.readFile(new URL('../apps/dashboard/assets/styles/dashboard.css',import.meta.url),'utf8');
 const root=css.match(/:root\s*\{([^}]+)\}/)[1],light=css.match(/html\[data-theme="light"\]\s*\{([^}]+)\}/)[1];const variables=s=>new Map([...s.matchAll(/--([\w-]+)\s*:\s*(#[0-9a-f]{6})/gi)].map(m=>[m[1],m[2]]));
 for(const theme of [variables(root),new Map([...variables(root),...variables(light)])])for(const level of ['info','success','warning','error','debug'])for(const bg of ['bg-primary','bg-hover'])assert(ratio(theme.get('log-'+level),theme.get(bg))>=4.5,`${level} against ${bg}`);
 for(const level of ['info','success','warning','error','debug'])assert(dashboard.includes(`.log-level.${level}{color:var(--log-${level})}`));
});
await check('owner metrics render retained record scope rather than lifetime claims',async()=>{
 const source=await fs.readFile(new URL('../apps/dashboard/assets/js/pages/admin-analytics.js',import.meta.url),'utf8');const selected=source.slice(source.indexOf('function metric('),source.indexOf('function chartBounds('));const metrics={innerHTML:''};const ctx=vm.createContext({els:{metrics},range:'all',esc:String,num:String,pct:()=>'',duration:String,dateTime:String});vm.runInContext(selected,ctx);ctx.renderMetrics({range:'all',allTime:{uniqueUsers:3,totalLaunches:8},selectedRange:{}});
 assert(metrics.innerHTML.includes('retained history'));assert(metrics.innerHTML.includes('First recorded user appearance in range'));assert(!/users ever|First-ever|all time/i.test(metrics.innerHTML));
 const html=await fs.readFile(new URL('../apps/dashboard/admin/index.html',import.meta.url),'utf8');assert(!html.includes('Every unique Roblox user ever seen'));
});
await fs.writeFile(new URL('accessibility-ui-results.json',import.meta.url),JSON.stringify({date:'2026-10-02',passed:checks.length,checks,scope:'Actual components in LinkeDOM with explicit focus-event model and CSS numeric contrast. No real browser or screen-reader verification.'},null,2)+'\n');console.log(JSON.stringify({passed:checks.length,checks}));

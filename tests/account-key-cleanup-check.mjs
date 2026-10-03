import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {parseHTML} from 'linkedom';
const disclosure=(await fs.readFile(new URL('../apps/dashboard/assets/js/core/disclosure.js',import.meta.url),'utf8')).replace(/^export /gm,'');
const source=(await fs.readFile(new URL('../apps/dashboard/assets/js/components/account.js',import.meta.url),'utf8')).replace(/^import .*;\r?\n/gm,'').replace(/^export /gm,'');
const flush=async()=>{for(let i=0;i<10;i++)await Promise.resolve()};
function fixture(){
  const {document,window,HTMLElement}=parseHTML('<html><body><div class="header-actions"></div></body></html>');let active=document.body;Object.defineProperty(document,'activeElement',{get:()=>active});HTMLElement.prototype.focus=function(){active=this};
  const listeners=[],snap={status:'authenticated',token:'session-A',user:{id:'A',username:'synthetic',dashboardKey:{exists:false}}};
  const emit=()=>listeners.forEach(fn=>fn(snap));const guest=()=>{snap.status='guest';snap.token='';snap.user=null;emit()};
  const authService={getSnapshot:()=>snap,subscribe:fn=>listeners.push(fn),init:async()=>snap,generateDashboardKey:async()=>({dashboardKey:'synthetic-revealed-secret'}),logout:async()=>guest(),login(){}};
  const ctx=vm.createContext({document,window,authService,console,location:{pathname:'/dashboard/',search:''},navigator:{clipboard:{writeText:async()=>{}}},toast(){}});vm.runInContext(disclosure+source,ctx);ctx.mountAccount();
  const click=selector=>document.querySelector(selector).dispatchEvent(new window.Event('click',{bubbles:true}));
  return{document,snap,emit,guest,click,panel:document.querySelector('.account-panel')};
}
const checks=[];
for(const scenario of ['local logout','cross-tab logout','local account clear','new user','same user new session','closed panel logout']){
  const f=fixture();f.click('[data-account-trigger]');f.click('[data-key-generate]');await flush();assert.equal(f.panel.querySelector('.account-key-reveal code').textContent,'synthetic-revealed-secret');
  if(scenario==='closed panel logout')f.click('[data-account-trigger]');
  if(scenario==='local logout')f.click('[data-account-logout]');
  else if(scenario==='new user'||scenario==='same user new session'){f.snap.token='session-B';if(scenario==='new user')f.snap.user={id:'B',username:'second'};f.emit();}
  else f.guest();
  await flush();assert.equal(f.panel.dataset.open,'false');assert(f.panel.hasAttribute('inert'));assert.equal(f.panel.querySelector('.account-key-reveal'),null);assert(!f.panel.textContent.includes('synthetic-revealed-secret'));assert.equal(f.document.querySelector('[data-account-trigger]').getAttribute('aria-expanded'),'false');checks.push(scenario);
}
{
  const f=fixture();f.click('[data-account-trigger]');f.click('[data-key-generate]');await flush();f.snap.user={...f.snap.user,displayName:'updated'};f.emit();assert.equal(f.panel.querySelector('.account-key-reveal code').textContent,'synthetic-revealed-secret');checks.push('ordinary same-identity refresh keeps the freshly generated key available');
}
const report={passed:checks.length,checks,scope:'Actual account/disclosure modules in LinkeDOM; synthetic identities and key, without browser or API.'};console.log(JSON.stringify(report));await fs.writeFile(new URL('account-key-cleanup-results.json',import.meta.url),JSON.stringify(report,null,2)+'\n');

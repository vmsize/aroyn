import { disposePage } from '../core/page-lifecycle.js';
import { icons } from '../core/icons.js';
import { storage } from '../core/storage.js';
import { mountSettings } from './settings.js';
import { initSystemTheme } from '../core/theme.js';
import { initToasts } from '../core/toast.js';
import { runtimeService } from '../services/runtime-service.js';
import { mountAccount } from './account.js';
import { authService } from '../services/auth-service.js';
import { mountRobloxAccountSelector } from './roblox-account-selector.js';

const nav=[
  ['overview','Overview',icons.overview,'/dashboard/'],
  ['stats','Stats',icons.stats,'/dashboard/stats/'],
  ['inventory','Inventory',icons.inventory,'/dashboard/inventory/'],
  ['runtime','Runtime',icons.runtime,'/dashboard/runtime/'],
  ['activity','Activity',icons.activity,'/dashboard/activity/'],
  ['modules','Modules',icons.modules,'/dashboard/modules/'],
  ['logs','Logs',icons.logs,'/dashboard/logs/'],
  ['configuration','Configuration',icons.config,'/dashboard/configuration/']
];
let routeSequence=0;


const discordMark=`<svg class="discord-auth-icon" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M20.3 4.37A19.8 19.8 0 0 0 15.38 2.8a13.6 13.6 0 0 0-.63 1.3 18.4 18.4 0 0 0-5.49 0 13.2 13.2 0 0 0-.64-1.3A19.7 19.7 0 0 0 3.7 4.38C.58 9.02-.27 13.55.15 18.02a19.9 19.9 0 0 0 6.04 3.05c.49-.66.92-1.36 1.3-2.1a12.9 12.9 0 0 1-2.04-.98l.5-.39c3.94 1.82 8.22 1.82 12.11 0l.51.39c-.65.38-1.33.71-2.04.98.38.74.81 1.44 1.3 2.1a19.8 19.8 0 0 0 6.04-3.05c.5-5.18-.86-9.67-3.57-13.65ZM8.02 15.27c-1.18 0-2.15-1.09-2.15-2.43 0-1.34.95-2.43 2.15-2.43 1.21 0 2.17 1.1 2.15 2.43 0 1.34-.95 2.43-2.15 2.43Zm7.96 0c-1.18 0-2.15-1.09-2.15-2.43 0-1.34.95-2.43 2.15-2.43 1.21 0 2.17 1.1 2.15 2.43 0 1.34-.94 2.43-2.15 2.43Z"/></svg>`;

let authGateInitialized=false;
function ensureAuthGate(){
  let gate=document.querySelector('[data-dashboard-auth-gate]');
  if(gate)return gate;
  gate=document.createElement('main');
  gate.className='dashboard-auth-gate';
  gate.dataset.dashboardAuthGate='';
  gate.setAttribute('aria-live','polite');
  document.body.append(gate);
  return gate;
}
function renderAuthGate(state='loading',message=''){
  const gate=ensureAuthGate();
  if(state==='loading'){
    gate.innerHTML=`<div class="dashboard-auth-loading"><img src="/assets/aroyn-mark.png" alt=""/><span>Checking Aroyn session…</span></div>`;
    return;
  }
  const error=message?`<div class="dashboard-auth-error" role="alert">${String(message).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#039;','"':'&quot;'}[c]))}</div>`:'';
  gate.innerHTML=`<section class="dashboard-login-card" aria-labelledby="dashboard-login-title">
    <div class="dashboard-login-brand"><img src="/assets/aroyn-mark.png" alt="Aroyn"/><span>Aroyn</span></div>
    <div class="dashboard-login-copy">
      <p class="dashboard-login-eyebrow">Dashboard access</p>
      <h1 id="dashboard-login-title">Sign in to Aroyn</h1>
      <p>Your dashboard is private. Sign in with Discord to access your Aroyn account, runtime data, inventory, statistics, logs, and dashboard key.</p>
    </div>
    ${error}
    <p class="dashboard-login-data-notice">Discord shares your ID, username, display name and avatar. Aroyn uses login cookies and saves your session in this browser. Before signing in, read the notices below.</p>
    <nav class="dashboard-login-policy-links" aria-label="Before sign-in"><a href="/privacy/">Privacy</a><a href="/terms/">Terms</a><a href="/cookies/">Cookies &amp; storage</a></nav>
    <button class="dashboard-discord-button" type="button" data-dashboard-discord-login>${discordMark}<span>Sign in with Discord</span></button>
    <p class="dashboard-login-note">Only the Discord identity scope is requested — no email, server list or messages. Age and guardian requirements are explained in Terms.</p>
  </section>`;
  gate.querySelector('[data-dashboard-discord-login]')?.addEventListener('click',()=>authService.login(location.pathname+location.search));
}
function showAuthenticatedDashboard(){
  document.body.dataset.authState='authenticated';
  document.querySelector('[data-dashboard-auth-gate]')?.remove();
}

let runtimeBootOverlay=null;
let runtimeBootStartedAt=0;

function showRuntimeBootOverlay(){
  if(runtimeBootOverlay?.isConnected)return runtimeBootOverlay;

  runtimeBootStartedAt=performance.now();
  const overlay=document.createElement('div');
  overlay.className='dashboard-runtime-loader';
  overlay.dataset.runtimeLoader='';
  overlay.setAttribute('role','status');
  overlay.setAttribute('aria-live','polite');
  overlay.setAttribute('aria-label','Loading Aroyn dashboard');

  overlay.innerHTML=`
    <div class="dashboard-runtime-loader-inner">
      <div class="dashboard-runtime-loader-mark-wrap">
        <img class="dashboard-runtime-loader-mark" src="/assets/aroyn-mark.png" alt=""/>
      </div>
      <div class="dashboard-runtime-loader-dots" aria-hidden="true">
        <span></span><span></span><span></span>
      </div>
    </div>`;

  document.body.append(overlay);
  runtimeBootOverlay=overlay;
  requestAnimationFrame(()=>overlay.dataset.visible='true');
  return overlay;
}

async function hideRuntimeBootOverlay(){
  const overlay=runtimeBootOverlay;
  if(!overlay)return;

  // Avoid a jarring one-frame flash on very fast connections.
  const minimumVisible=520;
  const elapsed=performance.now()-runtimeBootStartedAt;
  if(elapsed<minimumVisible){
    await new Promise(resolve=>setTimeout(resolve,minimumVisible-elapsed));
  }

  overlay.dataset.visible='false';
  await new Promise(resolve=>setTimeout(resolve,220));
  overlay.remove();
  if(runtimeBootOverlay===overlay)runtimeBootOverlay=null;
}

async function waitForDashboardHydration(){
  showRuntimeBootOverlay();

  // Never leave the user trapped behind a loader if an upstream request hangs.
  await Promise.race([
    runtimeService.waitForInitialSync(),
    new Promise(resolve=>setTimeout(()=>resolve({reason:'timeout'}),9500))
  ]);

  await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
  await hideRuntimeBootOverlay();
}
function showGuestDashboard(message=''){
  if(!message){try{message=sessionStorage.getItem('aroyn.accountDeletionNotice')??sessionStorage.getItem('veyra.accountDeletionNotice')??'';sessionStorage.removeItem('aroyn.accountDeletionNotice');sessionStorage.removeItem('veyra.accountDeletionNotice')}catch{}}
  document.body.dataset.authState='guest';
  renderAuthGate('guest',message);
  hideSplash();
}

export function mountDashboardShell(active){
  const shell=document.querySelector('.app-shell');
  if(!shell)return;
  if(shell.dataset.mounted==='true'){showAuthenticatedDashboard();setActiveNav(active);return;}
  if(authGateInitialized)return;
  authGateInitialized=true;
  document.body.dataset.authState='pending';
  renderAuthGate('loading');
  authService.init().then(snap=>{
    if(snap.status==='authenticated'&&snap.user){
      showAuthenticatedDashboard();
      showRuntimeBootOverlay();
      mountAuthenticatedShell(active);
      waitForDashboardHydration();
      window.addEventListener('aroyn:auth-logout',()=>location.reload(),{once:true});
    }else{
      showGuestDashboard();
    }
  }).catch(err=>showGuestDashboard(err instanceof Error?err.message:String(err)));
  window.addEventListener('aroyn:auth-error',e=>showGuestDashboard(e.detail?.message||'Discord sign-in failed.'),{once:true});
}

function mountAuthenticatedShell(active){
  const shell=document.querySelector('.app-shell');const sidebar=document.querySelector('.sidebar');if(!shell||!sidebar)return;
  if(shell.dataset.mounted==='true'){setActiveNav(active);return;}
  shell.dataset.mounted='true';

  const navEl=sidebar.querySelector('[data-nav]');
  navEl.innerHTML=`<div class="nav-section-label">Workspace</div>`+nav.map(([key,label,icon,href])=>`<a class="nav-item" href="${href}" data-nav-key="${key}" data-tooltip="${label}">${icon}<span class="nav-label">${label}</span></a>`).join('');
  setActiveNav(active);

  const collapsed=storage.get('sidebar.collapsed',false);shell.dataset.collapsed=String(collapsed);
  const collapse=sidebar.querySelector('[data-collapse]');collapse.innerHTML=`${icons.collapse}<span>Collapse sidebar</span>`;
  requestAnimationFrame(()=>{shell.dataset.sidebarReady='true'});
  collapse.addEventListener('click',()=>{
    const v=shell.dataset.collapsed!=='true';
    shell.dataset.collapsed=String(v);
    collapse.setAttribute('aria-label',v?'Expand sidebar':'Collapse sidebar');
    storage.set('sidebar.collapsed',v);
  });

  const menu=document.querySelector('[data-mobile-menu]');const backdrop=document.querySelector('.drawer-backdrop');
  const drawer=v=>{
    shell.dataset.drawer=String(v);
    menu?.setAttribute('aria-expanded',String(v));
    document.body.dataset.mobileNav=String(v);
  };
  menu?.addEventListener('click',()=>drawer(shell.dataset.drawer!=='true'));
  backdrop?.addEventListener('click',()=>drawer(false));
  window.addEventListener('resize',()=>{if(innerWidth>760)drawer(false)});
  window.addEventListener('keydown',event=>{if(event.key==='Escape'&&shell.dataset.drawer==='true')drawer(false)});
  if(menu)menu.innerHTML=icons.menu;

  const settings=document.querySelector('[data-settings-trigger]');if(settings)settings.innerHTML=`${icons.settings}<span class="sr-only">Settings</span>`;
  mountSettings();initSystemTheme();initToasts();mountRobloxAccountSelector();mountAccount();authService.init();mountTooltips(shell);mountDashboardRouter(shell,drawer);mountConnectionIndicator();hideSplash();
}

function mountConnectionIndicator(){
  const host=document.querySelector('.connection-compact');if(!host||host.dataset.live==='true')return;host.dataset.live='true';
  const render=s=>{const c=s.connection||{state:'disconnected',label:'Offline'};host.innerHTML=`<span class="status ${c.state}"><span class="status-dot"></span><span>${c.label}</span></span>`};
  render(runtimeService.getSnapshot());runtimeService.subscribe(render);
}

export function setActiveNav(active){document.querySelectorAll('[data-nav-key]').forEach(a=>{if(a.dataset.navKey===active)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current')})}

function mountTooltips(shell){let tip;document.addEventListener('mouseover',e=>{if(shell.dataset.collapsed!=='true'||innerWidth<=760)return;const el=e.target.closest?.('[data-tooltip]');if(!el)return;tip?.remove();tip=document.createElement('div');tip.className='tooltip';tip.textContent=el.dataset.tooltip;document.body.append(tip);const r=el.getBoundingClientRect();tip.style.left=`${r.right+8}px`;tip.style.top=`${r.top+r.height/2}px`});document.addEventListener('mouseout',e=>{if(e.target.closest?.('[data-tooltip]')){tip?.remove();tip=null}})}

function pageKeyFromPath(pathname){const p=pathname.replace(/\/+$/,'');if(p==='/dashboard'||p==='')return'overview';const part=p.split('/').filter(Boolean).at(-1);return nav.some(([key])=>key===part)?part:'overview'}

function scriptFromDocument(doc){const node=[...doc.querySelectorAll('script[type="module"][src]')].find(s=>s.getAttribute('src')?.includes('/assets/js/pages/'));return node?.getAttribute('src')||null}

function setRouteProgress(state){const bar=document.querySelector('.route-progress');if(!bar)return;bar.classList.remove('is-active','is-done');if(state==='start')bar.classList.add('is-active');if(state==='done'){bar.classList.add('is-done');setTimeout(()=>bar.classList.remove('is-done'),180)}}

function mountDashboardRouter(shell,drawer){
  if(shell.dataset.router==='true')return;shell.dataset.router='true';
  const main=document.querySelector('#main-content');if(!main)return;
  let navigating=false;

  const finishAnimations=animations=>Promise.allSettled(animations.map(animation=>animation.finished));

  async function leaveCurrentContent(reduce){
    if(reduce)return null;
    const animation=main.animate([
      {opacity:1,transform:'translateY(0)',filter:'blur(0px)'},
      {opacity:0,transform:'translateY(-5px)',filter:'blur(2px)'}
    ],{
      duration:135,
      easing:'cubic-bezier(.4,0,.6,1)',
      fill:'forwards'
    });
    try{await animation.finished}catch{}
    return animation;
  }

  async function revealNextContent(reduce,leaveAnimation){
    if(reduce){leaveAnimation?.cancel();return}

    // Animate the major page blocks independently. This keeps the transition
    // calm and gives new content the same staged arrival used on the home page.
    const children=[...main.children].filter(node=>node instanceof HTMLElement);
    const animations=children.map((child,index)=>child.animate([
      {opacity:0,transform:'translateY(7px)',filter:'blur(3px)'},
      {opacity:1,transform:'translateY(0)',filter:'blur(0px)'}
    ],{
      duration:210,
      delay:Math.min(index,5)*18,
      easing:'cubic-bezier(.2,.7,.2,1)',
      fill:'backwards'
    }));

    // Every incoming block already has backwards fill, so cancelling the old
    // page animation here cannot expose a single unanimated frame.
    leaveAnimation?.cancel();
    await finishAnimations(animations);
  }

  async function navigate(target,{push=true}={}){
    const url=target instanceof URL?target:new URL(target,location.href);
    if(url.href===location.href&&push)return;
    if(navigating)return;
    navigating=true;
    setRouteProgress('start');

    try{
      // Fetch first so the current page remains perfectly still while waiting
      // for the next document. The visible transition only starts once ready.
      const response=await fetch(url.pathname+url.search,{headers:{'X-Aroyn-Navigation':'soft'}});if(!response.ok)throw new Error(`HTTP ${response.status}`);
      const html=await response.text();const doc=new DOMParser().parseFromString(html,'text/html');const next=doc.querySelector('#main-content');if(!next)throw new Error('Missing main content');
      const script=scriptFromDocument(doc);const title=doc.title||'Aroyn';
      const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;

      // Hold the old page height during the cross-page handoff. Together with
      // scrollbar-gutter this prevents the entire dashboard from nudging when
      // switching between short and tall sections.
      const oldHeight=Math.ceil(main.getBoundingClientRect().height);
      main.style.minHeight=`${oldHeight}px`;

      const leaveAnimation=await leaveCurrentContent(reduce);

      disposePage();
      main.innerHTML=next.innerHTML;
      document.title=title;
      if(push)history.pushState({aroyn:true},'',url.pathname+url.search+url.hash);
      setActiveNav(pageKeyFromPath(url.pathname));
      drawer(false);
      if(scrollY>58)window.scrollTo({top:0,behavior:'instant'});

      // Route modules populate the freshly inserted DOM. Reveal only after the
      // page-specific data has been rendered, so cards/tables don't pop in late.
      if(script){routeSequence+=1;await import(`${script}?route=${routeSequence}`)}
      await revealNextContent(reduce,leaveAnimation);

      main.style.minHeight='';
      setRouteProgress('done');
    }catch(err){
      main.style.minHeight='';
      console.warn('[Aroyn] Soft navigation failed, falling back to document navigation.',err);
      location.href=url.href;
    }finally{
      navigating=false;
    }
  }

  document.addEventListener('click',e=>{
    if(e.defaultPrevented||e.button!==0||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;
    const a=e.target.closest?.('a[href]');if(!a||a.target==='_blank'||a.hasAttribute('download'))return;
    const url=new URL(a.href,location.href);if(url.origin!==location.origin||!url.pathname.startsWith('/dashboard/'))return;
    e.preventDefault();navigate(url);
  });
  addEventListener('popstate',()=>navigate(new URL(location.href),{push:false}));
}

export function hideSplash(){requestAnimationFrame(()=>document.querySelector('.app-splash')?.classList.add('is-hidden'));setTimeout(()=>document.querySelector('.app-splash')?.remove(),220)}

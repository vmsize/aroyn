import { mountDisclosure, preservePanelFocus } from '../core/disclosure.js';
import { authService } from '../services/auth-service.js';
import { toast } from '../core/toast.js';

function esc(value){return String(value??'').replace(/[&<>'"]/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[ch]))}
function initials(user){const source=user?.displayName||user?.username||'A';return source.trim().slice(0,1).toUpperCase()||'A'}

const discordMark=`<svg class="icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.317 4.369A19.791 19.791 0 0 0 15.885 3c-.191.328-.403.769-.552 1.116a18.27 18.27 0 0 0-5.32 0A12.64 12.64 0 0 0 9.46 3a19.736 19.736 0 0 0-4.433 1.369C2.223 8.479 1.48 12.487 1.851 16.438a19.93 19.93 0 0 0 5.43 2.77c.439-.599.823-1.233 1.151-1.897-.63-.239-1.231-.536-1.794-.885.15-.109.297-.222.439-.339 3.458 1.611 7.213 1.611 10.63 0 .143.117.289.23.439.339-.563.349-1.165.646-1.794.885.328.664.712 1.298 1.151 1.897a19.899 19.899 0 0 0 5.43-2.77c.436-4.58-.743-8.551-3.603-12.069ZM8.02 14.121c-1.037 0-1.887-.955-1.887-2.127 0-1.172.831-2.127 1.887-2.127 1.065 0 1.906.964 1.887 2.127 0 1.172-.831 2.127-1.887 2.127Zm7.96 0c-1.037 0-1.887-.955-1.887-2.127 0-1.172.831-2.127 1.887-2.127 1.065 0 1.906.964 1.887 2.127 0 1.172-.822 2.127-1.887 2.127Z"/></svg>`

export function mountAccount(){
  const actions=document.querySelector('.header-actions');
  if(!actions)return;
  let trigger=actions.querySelector('[data-account-trigger]');
  if(!trigger){
    trigger=document.createElement('button');
    trigger.type='button';trigger.className='account-trigger';trigger.dataset.accountTrigger='';trigger.setAttribute('aria-expanded','false');
    actions.append(trigger);
  }
  let panel=document.querySelector('.account-panel');
  if(!panel){panel=document.createElement('section');panel.className='account-panel';panel.dataset.open='false';panel.setAttribute('aria-label','Aroyn account');document.body.append(panel)}

  let lastKey='';let confirmReplace=false;

  const disclosure = mountDisclosure({ trigger, panel, id: 'aroyn-account-panel' });
  const close=()=>{disclosure.close();confirmReplace=false};
  const open=()=>{confirmReplace=false;renderPanel(authService.getSnapshot());disclosure.open()};

  trigger.addEventListener('click',e=>{
    e.stopPropagation();
    const snap=authService.getSnapshot();
    if(snap.status==='guest'){authService.login(location.pathname+location.search);return}
    panel.dataset.open==='true'?close():open();
  });
  document.addEventListener('click',e=>{
    const path=typeof e.composedPath==='function'?e.composedPath():[];
    const clickedPanel=path.includes(panel)||panel.contains(e.target);
    const clickedTrigger=path.includes(trigger)||trigger.contains(e.target);
    if(panel.dataset.open==='true'&&!clickedPanel&&!clickedTrigger)close();
  },true);


  function renderTrigger(snap){
    const u=snap.user;
    if(snap.status==='loading'){
      trigger.className='account-trigger is-loading';trigger.innerHTML='<span class="account-avatar account-avatar-fallback">…</span><span class="account-name">Loading</span>';trigger.title='Loading Aroyn account';return;
    }
    if(!u){
      trigger.className='account-trigger is-guest';trigger.innerHTML=`<span class="account-discord-mark">${discordMark}</span><span class="account-name">Sign in</span>`;trigger.title='Sign in with Discord';return;
    }
    const avatar=u.avatarUrl?`<img class="account-avatar" src="${esc(u.avatarUrl)}" alt="">`:`<span class="account-avatar account-avatar-fallback">${esc(initials(u))}</span>`;
    trigger.className='account-trigger';trigger.innerHTML=`${avatar}<span class="account-name">${esc(u.displayName||u.username)}</span>`;trigger.title=`${u.displayName||u.username} · Aroyn account`;
  }

  function renderPanel(snap){preservePanelFocus(panel,()=>renderPanelContent(snap))}
  function renderPanelContent(snap){
    const u=snap.user;
    if(!u){panel.innerHTML='<div class="account-empty"><strong>Aroyn account</strong><p>Sign in with Discord to manage your dashboard connection.</p><button class="btn btn-primary" data-account-login data-focus-key="account-login">Sign in with Discord</button></div>';panel.querySelector('[data-account-login]')?.addEventListener('click',()=>authService.login(location.pathname+location.search));return}
    const avatar=u.avatarUrl?`<img class="account-panel-avatar" src="${esc(u.avatarUrl)}" alt="">`:`<span class="account-panel-avatar account-avatar-fallback">${esc(initials(u))}</span>`;
    const keyStatus=u.dashboardKey?.exists?`••••••-${esc(u.dashboardKey.suffix||'')}`:'Not generated';
    const reveal=lastKey?`<div class="account-key-reveal"><div><span>New dashboard key</span><code>${esc(lastKey)}</code></div><button class="btn" type="button" data-key-copy data-focus-key="key-copy">Copy</button></div><p class="account-key-note">Copy it now. Aroyn does not show the full key again.</p>`:'';
    const replace=u.dashboardKey?.exists;
    const replaceArea=confirmReplace?`<div class="account-key-confirm"><strong>Replace dashboard key?</strong><p>The previous key will stop working immediately. Existing account data stays intact.</p><div><button class="btn" type="button" data-key-cancel data-focus-key="key-cancel">Cancel</button><button class="btn btn-danger" type="button" data-key-confirm data-focus-key="key-confirm">Replace key</button></div></div>`:`<button class="btn ${replace?'':'btn-primary'}" type="button" data-key-generate data-focus-key="key-generate">${replace?'Regenerate key':'Generate dashboard key'}</button>`;
    panel.innerHTML=`
      <div class="account-panel-head">${avatar}<div><strong>${esc(u.displayName||u.username)}</strong><span>@${esc(u.username)}</span></div></div>
      <div class="account-panel-body">
        <div class="account-kv"><span>Aroyn ID</span><code>${esc(u.id)}</code></div>
        <div class="account-kv"><span>Dashboard key</span><code>${keyStatus}</code></div>
        ${reveal}
        ${replaceArea}
      </div>
      <div class="account-panel-foot"><a class="btn btn-ghost" href="/dashboard/account/" data-account-data data-focus-key="account-data">Account data</a><button class="btn btn-ghost" type="button" data-account-logout data-focus-key="account-logout">Log out</button></div>`;

    panel.querySelector('[data-account-data]')?.addEventListener('click',close);

    panel.querySelector('[data-key-copy]')?.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(lastKey);toast('Dashboard key copied','Paste it in Aroyn Hub → Session.','success')}catch{toast('Copy failed','Select the key and copy it manually.','danger')}});
    panel.querySelector('[data-key-generate]')?.addEventListener('click',async()=>{
      if(replace){confirmReplace=true;renderPanel(authService.getSnapshot());panel.querySelector('[data-key-cancel]')?.focus();return}
      await generate(false);
    });
    panel.querySelector('[data-key-cancel]')?.addEventListener('click',()=>{confirmReplace=false;renderPanel(authService.getSnapshot())});
    panel.querySelector('[data-key-confirm]')?.addEventListener('click',()=>generate(true));
    panel.querySelector('[data-account-logout]')?.addEventListener('click',async()=>{lastKey='';close();await authService.logout();toast('Signed out','Your local Aroyn web session was removed.')});
  }

  async function generate(confirm){
    const button=panel.querySelector(confirm?'[data-key-confirm]':'[data-key-generate]');
    if(button){button.disabled=true;button.textContent=confirm?'Replacing…':'Generating…'}
    try{
      const result=await authService.generateDashboardKey(confirm);lastKey=result.dashboardKey||'';confirmReplace=false;renderPanel(authService.getSnapshot());toast(result.replaced?'Dashboard key replaced':'Dashboard key created',result.replaced?'The previous key no longer works.':'Paste the new key in Aroyn Hub → Session.','success');
    }catch(err){if(err?.code==='AUTH_CHANGED')return;toast('Dashboard key error',err instanceof Error?err.message:String(err),'danger');renderPanel(authService.getSnapshot())}
  }

  const sync=snap=>{if(snap.status==='guest'){lastKey='';confirmReplace=false;close()}renderTrigger(snap);if(panel.dataset.open==='true')renderPanel(snap)};
  sync(authService.getSnapshot());authService.subscribe(sync);authService.init();
  return{trigger,panel};
}

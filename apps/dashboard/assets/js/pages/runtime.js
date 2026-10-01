import { initPage, statusHTML, escapeHTML } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
import { authService } from '../services/auth-service.js';
import { transportLabel } from '../utils/transport-label.js';

initPage('runtime','Runtime');
const grid=document.querySelector('.overview-grid');
const originals=grid?[...grid.querySelectorAll(':scope > .panel')]:[];
const connectionPanel=originals[0],sessionPanel=originals[1],telemetryPanel=originals[2],bridgePanel=originals[3];

const accountPanel=document.createElement('section');
accountPanel.className='panel runtime-connect-panel';
grid?.prepend(accountPanel);

function kv(label,value){return`<div class="kv-row"><dt>${escapeHTML(label)}</dt><dd>${escapeHTML(value??'—')}</dd></div>`}
function renderAccount(){
  const a=authService.getSnapshot();
  if(a.status==='loading'){
    accountPanel.innerHTML='<div class="panel-header"><span class="panel-title">Aroyn account</span></div><div class="panel-body"><p class="secondary" style="margin:0">Loading account…</p></div>';return;
  }
  if(!a.user){
    accountPanel.innerHTML='<div class="panel-header"><span class="panel-title">Aroyn account</span><span class="tag">Required for personal telemetry</span></div><div class="panel-body"><div class="pair-layout"><div><strong>Sign in with Discord</strong><p class="field-help">The dashboard itself stays accessible without an account. Sign in only when you want your own runtime, Stats, and persistent dashboard identity.</p></div><div class="pair-controls account-runtime-actions"><button class="btn btn-primary" type="button" data-runtime-login>Sign in with Discord</button></div></div></div>';
    accountPanel.querySelector('[data-runtime-login]')?.addEventListener('click',()=>authService.login(location.pathname));return;
  }
  const u=a.user;const key=u.dashboardKey?.exists?`Configured · ••••••-${u.dashboardKey.suffix||''}`:'Not generated yet';
  accountPanel.innerHTML=`<div class="panel-header"><span class="panel-title">Aroyn account</span><span class="tag">Discord</span></div><div class="panel-body"><dl class="kv-list">${kv('Account',u.displayName||u.username)}${kv('Aroyn ID',u.id)}${kv('Dashboard key',key)}${kv('Runtime linking',u.dashboardKey?.exists?'Enter the key in Aroyn Hub → Session':'Generate a key from the avatar menu')}</dl></div>`;
}

authService.subscribe(renderAccount);authService.init().then(renderAccount);renderAccount();

function render(s){
  document.querySelector('[data-runtime-state]').innerHTML=statusHTML(s.connection.state,s.connection.label);
  if(connectionPanel){connectionPanel.querySelector('.panel-body').innerHTML=`<dl class="kv-list">${kv('Status',s.connection.label)}${kv('Transport',transportLabel(s))}${kv('Endpoint',s.bridge?.apiBase||'—')}${kv('Last message',s.bridge?.lastSeen?new Date(s.bridge.lastSeen).toLocaleTimeString():'—')}</dl>`}
  if(sessionPanel){sessionPanel.querySelector('.panel-body').innerHTML=`<dl class="kv-list">${kv('Session ID',s.session.id||'—')}${kv('Environment',s.session.environment||'—')}${kv('Started',s.session.started||'—')}${kv('Duration',s.session.duration||'—')}</dl>`}
  if(telemetryPanel){
    const live=s.live;if(!live){telemetryPanel.innerHTML=`<div class="panel-header"><span class="panel-title">Telemetry</span></div><div class="empty-state"><div class="empty-state-inner"><h3>No telemetry available</h3><p>${s.bridge?.account?'Open Aroyn Hub → Session and link the dashboard key from your account menu.':'Sign in with Discord to access your personal runtime.'}</p></div></div>`}
    else{const st=live.stats||{};telemetryPanel.innerHTML=`<div class="panel-header"><span class="panel-title">Telemetry</span><span class="tag">Live</span></div><div class="panel-body"><dl class="kv-list">${kv('Account',live.player?.name||'—')}${kv('Experience',live.product?.mode||'—')}${kv('Current task',live.runtime?.currentTask||'Idle')}${kv('Push latency',live.runtime?.pushLatencyMs!=null?`${Math.round(live.runtime.pushLatencyMs)} ms`:'—')}${kv('Cash',st.cash!=null?String(st.cash):'—')}${kv('Fruits collected',st.fruitsCollected!=null?String(st.fruitsCollected):'—')}</dl></div>`}
  }
  if(bridgePanel){bridgePanel.innerHTML=`<div class="panel-header"><span class="panel-title">Runtime identity</span></div><div class="panel-body">${s.live?`<dl class="kv-list">${kv('Display name',s.live.player?.displayName||'—')}${kv('User ID',s.live.player?.userId!=null?String(s.live.player.userId):'—')}${kv('Script',`${s.live.product?.name||'Aroyn Hub'} ${s.live.product?.version||''}`.trim())}${kv('Schema',String(s.live.schemaVersion||1))}</dl>`:`<p class="secondary" style="font-size:.8rem;line-height:1.65;margin:0">The website authenticates your Aroyn account. Aroyn Hub uses the separate dashboard key only for pushing runtime telemetry.</p>`}</div>`}
}
render(runtimeService.getSnapshot());runtimeService.subscribe(render);

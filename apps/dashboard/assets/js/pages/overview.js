import { initPage, statusHTML, escapeHTML } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
import { formatMoney } from '../utils/number-format.js';
import { transportLabel } from '../utils/transport-label.js';

initPage('overview','Dashboard');
const grid=document.querySelector('.overview-grid');
const panels=grid?[...grid.querySelectorAll(':scope > .panel')]:[];
const runtimePanel=panels[0],systemPanel=panels[1],activityPanel=panels[2],integrationPanel=panels[3];


function wholeNumber(value){
  if(value==null||value==='')return '0';
  const n=Number(value);
  if(!Number.isFinite(n))return String(value);
  return n.toLocaleString(undefined,{maximumFractionDigits:0});
}

function text(value,fallback='—'){return value==null||value===''?fallback:String(value)}
function metric(label,value,note=''){return`<div class="stat-block"><div class="stat-label">${escapeHTML(label)}</div><div class="stat-value">${escapeHTML(text(value))}</div>${note?`<div class="stat-note">${escapeHTML(note)}</div>`:''}</div>`}
function activityRows(items){return(items||[]).slice(-8).map(e=>`<div class="event-row"><span class="event-time">${escapeHTML(e.time)}</span><span class="event-marker ${escapeHTML(e.kind)}"></span><div><div class="event-title">${escapeHTML(e.title)}</div><div class="event-detail">${escapeHTML(e.detail||'')}</div></div></div>`).join('')}

function render(s){
  document.querySelector('[data-runtime-status]').innerHTML=statusHTML(s.connection.state,s.connection.label);
  const banner=document.querySelector('.runtime-banner');
  if(banner){
    banner.className=`runtime-banner ${s.connection.state==='connected'?'is-live':''}`;
    banner.innerHTML=`<span class="status-dot"></span><div><strong>${escapeHTML(s.connection.label)}</strong><p>${escapeHTML(s.connection.detail||'')}</p></div>`;
  }
  if(runtimePanel){
    const task=s.task?.name||'None';
    runtimePanel.querySelector('.panel-header').innerHTML=`<span class="panel-title">Runtime status</span><span class="tag">${s.connection.state==='connected'?'Live':'Local / waiting'}</span>`;
    runtimePanel.querySelector('.panel-body').innerHTML=`<div class="stats-grid">${metric('State',s.connection.label,s.connection.detail||'')}${metric('Session',s.session.duration||'—',s.session.started?'Live runtime session':'No active runtime')}${metric('Current task',task,s.task?.detail||'No active task')}</div><dl class="kv-list section-spacer"><div class="kv-row"><dt>Started</dt><dd>${escapeHTML(text(s.session.started))}</dd></div><div class="kv-row"><dt>Duration</dt><dd>${escapeHTML(text(s.session.duration))}</dd></div><div class="kv-row"><dt>Environment</dt><dd>${escapeHTML(text(s.session.environment))}</dd></div></dl>`;
  }
  if(systemPanel){
    systemPanel.querySelector('.panel-body').innerHTML=`<dl class="kv-list"><div class="kv-row"><dt>CPU</dt><dd>${escapeHTML(text(s.system.cpu,'Unavailable'))}</dd></div><div class="kv-row"><dt>Memory</dt><dd>${escapeHTML(text(s.system.memory,'Unavailable'))}</dd></div><div class="kv-row"><dt>Latency</dt><dd>${escapeHTML(text(s.system.latency,'Unavailable'))}</dd></div><div class="kv-row"><dt>Transport</dt><dd>${escapeHTML(transportLabel(s))}</dd></div></dl>`;
  }
  if(activityPanel){
    const host=activityPanel.querySelector('[data-activity]');
    if(host)host.innerHTML=activityRows(s.activity)||'<div class="empty-state"><div class="empty-state-inner"><h3>No activity yet</h3><p>No runtime events have been received in this session.</p></div></div>';
  }
  if(integrationPanel){
    const live=s.live;
    integrationPanel.querySelector('.panel-body')?.remove();
    integrationPanel.querySelector('.empty-state')?.remove();
    const body=document.createElement('div');
    body.className='panel-body';
    if(live){
      body.innerHTML=`<dl class="kv-list"><div class="kv-row"><dt>Account</dt><dd>${escapeHTML(live.player?.displayName||live.player?.name||'—')}</dd></div><div class="kv-row"><dt>Username</dt><dd>${escapeHTML(live.player?.name||'—')}</dd></div><div class="kv-row"><dt>Experience</dt><dd>${escapeHTML(live.product?.mode||'—')}</dd></div><div class="kv-row"><dt>Script</dt><dd>${escapeHTML(`${live.product?.name||'Aroyn Hub'} ${live.product?.version||''}`.trim())}</dd></div></dl>`;
    }else if(s.bridge?.account){
      body.innerHTML=`<div class="empty-state compact-empty"><div class="empty-state-inner"><h3>Waiting for Aroyn Hub</h3><p>Your Aroyn account is signed in. Link its dashboard key in Aroyn Hub → Session and telemetry will appear automatically.</p></div></div>`;
    }else{
      body.innerHTML=`<div class="empty-state compact-empty"><div class="empty-state-inner"><h3>Connect a runtime</h3><p>Sign in with Discord, generate a dashboard key from your account menu, then link it in Aroyn Hub → Session.</p><a class="btn" href="/dashboard/runtime/">Open Runtime</a></div></div>`;
    }
    integrationPanel.append(body);
  }
  let livePanel=grid?.querySelector('[data-live-stats]');
  if(s.live?.stats){
    if(!livePanel){
      livePanel=document.createElement('section');
      livePanel.className='panel live-stats-panel';
      livePanel.dataset.liveStats='';
      grid.append(livePanel);
    }
    grid.classList.add('has-live-stats');
    const st=s.live.stats;
    livePanel.innerHTML=`<div class="panel-header"><span class="panel-title">Greedy Growers session</span><span class="tag">Live</span></div><div class="panel-body"><div class="live-metric-grid">${metric('Current cash',formatMoney(st.cash))}${metric('Net cash',formatMoney(st.netCash))}${metric('Seed spend',formatMoney(st.seedSpend))}${metric('Fruits collected',wholeNumber(st.fruitsCollected??0))}${metric('Fruit inventory',formatMoney(st.fruitInventoryValue))}</div></div>`;
  }else{
    grid?.classList.remove('has-live-stats');
    livePanel?.remove();
  }
}

render(runtimeService.getSnapshot());
runtimeService.subscribe(render);

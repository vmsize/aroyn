import { authService } from '../services/auth-service.js';

import { LIVE_BASE } from '../core/config.js';
import { safeAvatarUrl, safeScriptBloxUrl } from '../utils/owner-urls.js';
const LIVE_API=LIVE_BASE.replace(/\/+$/, '');
const $=selector=>document.querySelector(selector);
const els={
  gate:$('#ownerGate'),gateText:$('#ownerGateText'),login:$('#ownerLogin'),app:$('#ownerApp'),refresh:$('#ownerRefresh'),
  range:$('#ownerRange'),updated:$('#ownerUpdated'),liveSummary:$('#ownerLiveSummary'),metrics:$('#ownerMetrics'),
  concurrent:$('#ownerConcurrentChart'),launches:$('#ownerLaunchChart'),hourly:$('#ownerHourlyChart'),timezone:$('#ownerTimezone'),
  versions:$('#ownerVersions'),games:$('#ownerGames'),places:$('#ownerPlaces'),devices:$('#ownerDevices'),executors:$('#ownerExecutors'),
  activityWindows:$('#ownerActivityWindows'),peakRecords:$('#ownerPeakRecords'),milestones:$('#ownerMilestones'),
  scriptBloxPanel:$('#ownerScriptBloxPanel'),scriptBloxState:$('#ownerScriptBloxState'),scriptBloxMetrics:$('#ownerScriptBloxMetrics'),scriptBloxMeta:$('#ownerScriptBloxMeta'),scriptBloxUpdated:$('#ownerScriptBloxUpdated'),scriptBloxSubtitle:$('#ownerScriptBloxSubtitle'),scriptBloxOpen:$('#ownerScriptBloxOpen'),
  onlineRows:$('#ownerOnlineRows'),recentRows:$('#ownerRecentRows'),allUsers:$('#ownerAllUsers'),allUsersEmpty:$('#ownerAllUsersEmpty'),allUsersCount:$('#ownerAllUsersCount'),onlineCount:$('#ownerOnlineCount'),
  userSearch:$('#ownerUserSearch'),userFilters:[...document.querySelectorAll('[data-user-filter]')],deviceFilter:$('#ownerDeviceFilter')
};
let range='24h',refreshTimer=null,inFlight=false,lastData=null,queuedRefresh=false,userPaused=false,failures=0;
const userDirectoryState={query:'',online:false,dashboard:false,today:false,device:'all'};

for(const avatarRoot of [els.allUsers,els.onlineRows,els.recentRows]){
  avatarRoot?.addEventListener('error',event=>{
    const img=event.target;
    if(!(img instanceof HTMLImageElement)||!img.matches('[data-owner-avatar]'))return;
    if(img.dataset.fallback==='1')return;
    img.dataset.fallback='1';
    img.src='/assets/aroyn-mark.png';
  },true);
}

const nf=new Intl.NumberFormat(undefined,{maximumFractionDigits:1});
const compact=new Intl.NumberFormat(undefined,{notation:'compact',maximumFractionDigits:1});
const esc=value=>String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const num=value=>Number.isFinite(Number(value))?compact.format(Number(value)):'0';
const pct=(part,total)=>Number(total)>0?`${Math.round((Number(part)||0)/(Number(total)||1)*1000)/10}%`:'0%';
const duration=ms=>{ms=Math.max(0,Number(ms)||0);if(ms<60000)return `${Math.round(ms/1000)}s`;if(ms<3600000)return `${Math.round(ms/60000)}m`;if(ms<86400000)return `${(ms/3600000).toFixed(ms<10*3600000?1:0)}h`;return `${(ms/86400000).toFixed(1)}d`};
const dateTime=ms=>ms?new Date(Number(ms)).toLocaleString(undefined,{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}):'—';
const timeAgo=ms=>{const d=Date.now()-Number(ms||0);if(!ms)return'—';if(d<60000)return`${Math.max(0,Math.round(d/1000))}s ago`;if(d<3600000)return`${Math.round(d/60000)}m ago`;if(d<86400000)return`${Math.round(d/3600000)}h ago`;return`${Math.round(d/86400000)}d ago`};
const gameName=row=>row?.gameSlug?String(row.gameSlug).replace(/-/g,' '):(row?.gameId?`Game ${row.gameId}`:'Unknown');

const executorLabel=row=>row?.executorName&&String(row.executorName).toLowerCase()!=='unknown'
  ? `${row.executorName}${row.executorVersion?' · '+row.executorVersion:''}`:'Unknown';

function showGate(message,{login=false,error=false}={}){
  clearTimeout(refreshTimer);
  if(error){lastData=null;els.allUsers.replaceChildren();els.onlineRows.replaceChildren();els.recentRows.replaceChildren();}
  const loading=!login&&!error;
  els.gate.hidden=false;
  els.gate.classList.toggle('is-loading',loading);
  els.app.hidden=true;
  els.gateText.textContent=message;
  els.gateText.classList.toggle('owner-error',error);
  els.login.hidden=!login;
}
function showApp(){
  els.gate.classList.remove('is-loading');
  els.gate.hidden=true;
  els.login.hidden=true;
  els.app.hidden=false;
}

async function fetchAnalytics(){
  if(inFlight){queuedRefresh=true;return;}
  if(!authService.token||document.hidden)return;
  clearTimeout(refreshTimer);
  inFlight=true;els.refresh.disabled=true;
  const requestedRange=range;
  const requestedToken=authService.token;
  try{
    const tzOffsetMinutes=new Date().getTimezoneOffset();
    const response=await fetch(`${LIVE_API}/owner/analytics?range=${encodeURIComponent(range)}&tzOffsetMinutes=${tzOffsetMinutes}`,{
      headers:{Accept:'application/json',Authorization:`Bearer ${authService.token}`},cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer',signal:AbortSignal.timeout(12000)
    });
    const body=await response.json().catch(()=>({}));
    // A request begun before sign-out must never reopen private analytics.
    if(authService.token!==requestedToken)return;
    if(response.status===401){showGate('Your Aroyn session expired. Sign in again.',{login:true,error:true});return}
    if(response.status===403){showGate('This account does not have owner access.',{error:true});return}
    if(response.status===503){showGate(body.error||'Owner access is not configured on the backend.',{error:true});return}
    if(!response.ok||!body.ok||!body.analytics)throw new Error(body.error||`Analytics request failed (${response.status})`);
    if(requestedRange!==range){queuedRefresh=true;return;}
    lastData=body.analytics;failures=0;showApp();render(body.analytics);
  }catch(error){
    if(authService.token!==requestedToken)return;
    failures+=1;
    if(!lastData)showGate('Could not load analytics. Check your connection and try Refresh.',{error:true});
    else els.updated.textContent='Refresh failed · displayed data is from the previous successful check';
  }finally{
    inFlight=false;els.refresh.disabled=false;
    if(queuedRefresh){queuedRefresh=false;fetchAnalytics();}
    else if(authService.token&&!els.app.hidden)scheduleRefresh();
  }
}
function scheduleRefresh(){clearTimeout(refreshTimer);if(!document.hidden&&!userPaused)refreshTimer=setTimeout(fetchAnalytics,Math.min(120000,15000*2**Math.min(failures,3)));}

function metric(label,value,note='',live=false){return `<article class="owner-metric${live?' is-live':''}"><div class="owner-metric-label">${esc(label)}</div><div class="owner-metric-value">${esc(value)}</div><div class="owner-metric-note">${esc(note)}</div></article>`}
function renderMetrics(a){
  const o=a.online||{},all=a.allTime||{},r=a.selectedRange||{},p=a.peaks||{};
  const rangeLabel=(a.range||range)==='all'?'retained history':(a.range||range);
  const launchesPerUser=all.uniqueUsers>0?(all.totalLaunches/all.uniqueUsers).toFixed(all.totalLaunches/all.uniqueUsers>=10?1:2):'0';
  els.metrics.innerHTML=[
    metric('Online sessions',num(o.scriptSessions),'Every active script instance',true),
    metric('Online users',num(o.scriptUsers),'Unique Roblox users right now',true),
    metric('Online + dashboard',num(o.dashboardUsers),`${num(o.dashboardSessions)} linked sessions`,true),
    metric('Peak concurrent',num(p.scriptSessions),p.scriptSessionsAt?dateTime(p.scriptSessionsAt):'No peak recorded yet'),
    metric('Peak unique users',num(p.scriptUsers),p.scriptUsersAt?dateTime(p.scriptUsersAt):'No peak recorded yet'),
    metric('Recorded launches',num(all.totalLaunches),'Launches in retained history'),
    metric('Recorded users',num(all.uniqueUsers),'Distinct Roblox UserIds in retained history'),
    metric('Recorded dashboard users',num(all.dashboardUsers),`${num(all.dashboardLaunches)} linked launches`),
    metric('Dashboard adoption',pct(all.dashboardUsers,all.uniqueUsers),'Share of users in retained history'),
    metric('Returning users',num(all.returningUsers),'Users with 2+ retained launches'),
    metric('Launches / user',launchesPerUser,'Average retained launches per user'),
    metric('Runtime observed',duration(all.totalSeenMs),'Sum of recorded session time'),
    metric(`Launches · ${rangeLabel}`,num(r.launches),`${num(r.uniqueUsers)} unique users`),
    metric(`New users · ${rangeLabel}`,num(r.newUsers),'First recorded user appearance in range'),
    metric(`Dashboard · ${rangeLabel}`,num(r.dashboardUsers),`${pct(r.dashboardUsers,r.uniqueUsers)} of unique users`),
    metric('Avg session seen',duration(r.avgSessionMs),`Selected range: ${rangeLabel}`)
  ].join('');
}

function chartBounds(rows,keys){let max=0;for(const row of rows)for(const key of keys)max=Math.max(max,Number(row[key])||0);return Math.max(1,max)}
function linePath(rows,key,w,h,pad,max){if(!rows.length)return'';return rows.map((row,i)=>{const x=pad+(rows.length===1?0:(i/(rows.length-1))*(w-pad*2));const y=h-pad-((Number(row[key])||0)/max)*(h-pad*2);return`${i?'L':'M'}${x.toFixed(1)},${y.toFixed(1)}`}).join(' ')}
function areaPath(rows,key,w,h,pad,max){if(!rows.length)return'';const line=linePath(rows,key,w,h,pad,max);const firstX=pad,lastX=rows.length===1?pad:w-pad;return`${line} L${lastX},${h-pad} L${firstX},${h-pad} Z`}
function labelForBucket(ms,rangeName){const d=new Date(Number(ms));if(rangeName==='24h')return d.toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit'});if(rangeName==='7d')return d.toLocaleDateString(undefined,{weekday:'short',hour:'2-digit'});return d.toLocaleDateString(undefined,{month:'short',day:'numeric'})}
function renderLineChart(el,rows){
  if(!rows.length){el.innerHTML='<div class="owner-chart-empty">No historical samples yet.</div>';return}
  const w=900,h=260,pad=34,max=chartBounds(rows,['scriptSessions','dashboardSessions']);
  const grid=[0,.25,.5,.75,1].map(t=>{const y=h-pad-t*(h-pad*2);return `<line class="owner-chart-gridline" x1="${pad}" y1="${y}" x2="${w-pad}" y2="${y}"/><text class="owner-chart-axis" x="5" y="${y+3}">${Math.round(max*t)}</text>`}).join('');
  const idx=[0,Math.floor((rows.length-1)/2),rows.length-1].filter((v,i,a)=>a.indexOf(v)===i);
  const xlabels=idx.map(i=>{const x=pad+(rows.length===1?0:(i/(rows.length-1))*(w-pad*2));return `<text class="owner-chart-axis" x="${x}" y="${h-7}" text-anchor="${i===0?'start':i===rows.length-1?'end':'middle'}">${esc(labelForBucket(rows[i].bucket,range))}</text>`}).join('');
  el.innerHTML=`<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Concurrent Aroyn usage"><path class="owner-area-script" d="${areaPath(rows,'scriptSessions',w,h,pad,max)}"/>${grid}<path class="owner-line-script" d="${linePath(rows,'scriptSessions',w,h,pad,max)}"/><path class="owner-line-dashboard" d="${linePath(rows,'dashboardSessions',w,h,pad,max)}"/>${xlabels}</svg>`;
}
function renderLaunchChart(el,rows){
  if(!rows.length){el.innerHTML='<div class="owner-chart-empty">No launches in this range yet.</div>';return}
  const w=900,h=260,pad=34,max=Math.max(1,...rows.map(r=>Number(r.launches)||0));const gap=rows.length>80?0.5:2;const usable=w-pad*2;const bw=Math.max(1,usable/rows.length-gap);
  const grid=[0,.25,.5,.75,1].map(t=>{const y=h-pad-t*(h-pad*2);return `<line class="owner-chart-gridline" x1="${pad}" y1="${y}" x2="${w-pad}" y2="${y}"/><text class="owner-chart-axis" x="5" y="${y+3}">${Math.round(max*t)}</text>`}).join('');
  const bars=rows.map((r,i)=>{const val=Number(r.launches)||0;const bh=(val/max)*(h-pad*2);const x=pad+i*(usable/rows.length)+gap/2;const y=h-pad-bh;return `<rect class="owner-launch-bar" x="${x.toFixed(2)}" y="${y.toFixed(2)}" width="${bw.toFixed(2)}" height="${Math.max(1,bh).toFixed(2)}" rx="1"><title>${esc(labelForBucket(r.bucket,range))}: ${val} launches, ${Number(r.launchUsers)||0} users</title></rect>`}).join('');
  const idx=[0,Math.floor((rows.length-1)/2),rows.length-1].filter((v,i,a)=>a.indexOf(v)===i);const labels=idx.map(i=>{const x=pad+(rows.length===1?0:(i/(rows.length-1))*(w-pad*2));return `<text class="owner-chart-axis" x="${x}" y="${h-7}" text-anchor="${i===0?'start':i===rows.length-1?'end':'middle'}">${esc(labelForBucket(rows[i].bucket,range))}</text>`}).join('');
  el.innerHTML=`<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Aroyn launches over time">${grid}${bars}${labels}</svg>`;
}
function renderHourly(rows){
  const byHour=new Map((rows||[]).map(r=>[Number(r.hour),r]));const data=Array.from({length:24},(_,hour)=>byHour.get(hour)||{hour,users:0,launches:0});const max=Math.max(1,...data.map(r=>Number(r.users)||0));const peak=Math.max(...data.map(r=>Number(r.users)||0));
  els.hourly.innerHTML=data.map(r=>{const users=Number(r.users)||0,launches=Number(r.launches)||0;const height=Math.max(users?4:2,(users/max)*100);return `<div class="owner-hour-col${users===peak&&peak>0?' is-peak':''}" title="${String(r.hour).padStart(2,'0')}:00 — ${users} unique users, ${launches} launches"><div class="owner-hour-bar-wrap"><div class="owner-hour-bar" style="height:${height}%"></div></div><div class="owner-hour-label">${String(r.hour).padStart(2,'0')}</div></div>`}).join('');
  const tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'Local time';els.timezone.textContent=tz;
}
function renderActivityWindows(a){
  const w=a.activeWindows||{};
  els.activityWindows.innerHTML=[
    ['Last 24 hours',w.users24h,w.launches24h],
    ['Last 7 days',w.users7d,w.launches7d],
    ['Last 30 days',w.users30d,w.launches30d]
  ].map(([label,users,launches])=>`<article class="owner-window-card"><div class="owner-window-label">${esc(label)}</div><div class="owner-window-value">${num(users)} <span>users</span></div><div class="owner-window-note">${num(launches)} launches</div></article>`).join('');
}
function renderPeakRecords(a){
  const p=a.peaks||{};
  const rows=[
    ['Script sessions',p.scriptSessions,p.scriptSessionsAt],
    ['Unique users',p.scriptUsers,p.scriptUsersAt],
    ['Dashboard sessions',p.dashboardSessions,p.dashboardSessionsAt],
    ['Dashboard users',p.dashboardUsers,p.dashboardUsersAt]
  ];
  els.peakRecords.innerHTML=rows.map(([label,value,at])=>`<div class="owner-peak-row"><div><span>${esc(label)}</span><strong>${num(value)}</strong></div><time>${at?esc(dateTime(at)):'No peak yet'}</time></div>`).join('');
}
function nextGrowthMilestone(current,targets){
  const value=Math.max(0,Number(current)||0);
  const ladder=[...targets].sort((a,b)=>a-b);
  let previous=0;
  let target=ladder[0]||1;

  for(const step of ladder){
    if(value<step){
      target=step;
      break;
    }
    previous=step;
    target=step;
  }

  // Keep milestones moving forever instead of getting stuck on "Reached".
  if(value>=target){
    previous=target;
    do{
      target=Math.max(previous+1,Math.round(previous*2));
      previous=target===previous?previous-1:previous;
    }while(value>=target);
  }

  const span=Math.max(1,target-previous);
  const progress=Math.max(0,Math.min(100,((value-previous)/span)*100));
  return {current:value,previous,target,progress};
}
function renderMilestones(a){
  const all=a.allTime||{},p=a.peaks||{};
  const definitions=[
    {
      label:'Unique users',
      current:Number(all.uniqueUsers)||0,
      targets:[100,250,500,1000,2500,5000,10000,25000,50000,100000],
      targetLabel:value=>`${num(value)} unique Roblox users`
    },
    {
      label:'Total launches',
      current:Number(all.totalLaunches)||0,
      targets:[1000,2500,5000,10000,25000,50000,100000,250000,500000,1000000],
      targetLabel:value=>`${num(value)} Aroyn launches`
    },
    {
      label:'Concurrent peak',
      current:Number(p.scriptSessions)||0,
      targets:[50,100,250,500,1000,2500,5000,10000],
      targetLabel:value=>`${num(value)} scripts online at once`
    }
  ];

  const milestones=definitions.map(item=>{
    const step=nextGrowthMilestone(item.current,item.targets);
    const note=step.previous>0
      ? `${num(step.previous)} reached · next ${item.targetLabel(step.target)}`
      : item.targetLabel(step.target);
    return {...item,...step,note};
  });

  els.milestones.innerHTML=milestones.map(item=>{
    return `<article class="owner-milestone">
      <div class="owner-milestone-top">
        <div>
          <div class="owner-milestone-label">${esc(item.label)}</div>
          <div class="owner-milestone-note">${esc(item.note)}</div>
        </div>
        <span class="owner-milestone-state">${Math.round(item.progress)}%</span>
      </div>
      <div class="owner-milestone-values"><strong>${num(item.current)}</strong><span>/ ${num(item.target)}</span></div>
      <div class="owner-milestone-track"><div class="owner-milestone-fill" style="width:${item.progress}%"></div></div>
    </article>`;
  }).join('');
}

function signedDelta(value){
  if(value==null||!Number.isFinite(Number(value)))return null;
  const n=Number(value);
  return `${n>0?'+':''}${nf.format(n)}`;
}
function renderScriptBlox(a){
  const sb=a.scriptBlox||null;
  if(!els.scriptBloxPanel)return;

  if(!sb||sb.available===false){
    els.scriptBloxOpen.hidden=true;
    els.scriptBloxOpen.removeAttribute('href');
    els.scriptBloxState.hidden=false;
    els.scriptBloxMetrics.hidden=true;
    els.scriptBloxMeta.hidden=true;
    els.scriptBloxState.classList.toggle('owner-error',Boolean(sb?.error));
    els.scriptBloxState.textContent=sb?.error
      ? `ScriptBlox unavailable: ${sb.error}`
      : 'No ScriptBlox data yet.';
    els.scriptBloxUpdated.textContent='';
    return;
  }

  els.scriptBloxState.hidden=true;
  els.scriptBloxState.classList.remove('owner-error');
  els.scriptBloxMetrics.hidden=false;
  els.scriptBloxMeta.hidden=false;

  const likes=Number(sb.likes)||0;
  const dislikes=Number(sb.dislikes)||0;
  const votes=likes+dislikes;
  const rating=votes>0?(likes/votes)*100:null;
  const d24=sb.change24h||{};
  const d7=sb.change7d||{};

  const cards=[
    ['Views',num(sb.views),signedDelta(d24.views),'24h'],
    ['Likes',num(likes),signedDelta(d24.likes),'24h'],
    ['Dislikes',num(dislikes),signedDelta(d24.dislikes),'24h'],
    ['Like ratio',rating==null?'—':`${rating.toFixed(1)}%`,votes?`${num(votes)} votes`:null,'']
  ];

  els.scriptBloxMetrics.innerHTML=cards.map(([label,value,delta,period])=>`
    <article class="owner-scriptblox-metric">
      <div class="owner-scriptblox-metric-label">${esc(label)}</div>
      <div class="owner-scriptblox-metric-value">${esc(value)}</div>
      <div class="owner-scriptblox-metric-note">${delta!=null?`${esc(delta)} ${esc(period)}`:'Collecting history'}</div>
    </article>
  `).join('');

  const state=sb.patched?'Patched':(String(sb.visibility||'').toLowerCase()==='public'?'Active':(sb.visibility||'Unknown'));
  const tags=[
    `<span class="owner-sb-tag ${sb.patched?'danger':'ok'}">${esc(state)}</span>`,
    `<span class="owner-sb-tag ${sb.verified?'ok':''}">${sb.verified?'Verified':'Unverified'}</span>`,
    `<span class="owner-sb-tag">${esc(sb.scriptType||'unknown')}</span>`
  ].join('');

  const change7Text=d7.views==null?'7d history collecting':`${signedDelta(d7.views)} views · ${signedDelta(d7.likes)||'0'} likes in 7d`;
  els.scriptBloxMeta.innerHTML=`
    <div class="owner-scriptblox-title-row">
      <div>
        <div class="owner-scriptblox-title">${esc(sb.title||'Aroyn Hub')}</div>
        <div class="owner-scriptblox-owner">by ${esc(sb.ownerUsername||'Unknown')} · ${esc(change7Text)}</div>
      </div>
      <div class="owner-scriptblox-tags">${tags}</div>
    </div>
    <div class="owner-scriptblox-details">
      <span>Published ${esc(sb.createdAt?new Date(sb.createdAt).toLocaleDateString():'—')}</span>
      <span>${esc(sb.gameName||'Greedy Growers')}</span>
      <span>${esc(sb.slug||'')}</span>
    </div>
  `;

  const listingUrl=safeScriptBloxUrl(sb.pageUrl);
  els.scriptBloxOpen.hidden=!listingUrl;
  if(listingUrl)els.scriptBloxOpen.href=listingUrl;
  else els.scriptBloxOpen.removeAttribute('href');
  els.scriptBloxSubtitle.textContent='Greedy Growers listing performance';
  els.scriptBloxUpdated.textContent=sb.capturedAt?`Updated ${timeAgo(sb.capturedAt)}`:'';
}

function localDayKey(ms){
  if(!ms)return'';
  const d=new Date(Number(ms));
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}
function isFirstSeenToday(ms){return localDayKey(ms)===localDayKey(Date.now())}
function normalizeUserSearch(value){return String(value||'').trim().toLowerCase()}
function filteredAllUsers(allUsers){
  const q=normalizeUserSearch(userDirectoryState.query);
  return (allUsers||[]).filter(user=>{
    const row=typeof user==='string'?{userId:user}:user||{};
    if(userDirectoryState.online&&!row.online)return false;
    if(userDirectoryState.dashboard&&!row.dashboardLinked)return false;
    if(userDirectoryState.today&&!isFirstSeenToday(row.firstSeenAt))return false;
    if(userDirectoryState.device!=='all'&&String(row.device||'unknown').toLowerCase()!==userDirectoryState.device)return false;
    if(q){
      const haystack=[
        row.userId,row.robloxUserId,row.username,row.displayName
      ].map(normalizeUserSearch).join(' ');
      if(!haystack.includes(q))return false;
    }
    return true;
  });
}

function renderBreakdown(el,rows){
  if(!rows?.length){el.innerHTML='<div class="owner-breakdown-empty">No data yet.</div>';return}
  const max=Math.max(1,...rows.map(r=>Number(r.launches)||0));el.innerHTML=rows.map(r=>`<div class="owner-breakdown-row"><div class="owner-breakdown-name" title="${esc(r.label)}">${esc(r.label)}</div><div class="owner-breakdown-value">${num(r.launches)} launches · ${num(r.users)} users</div><div class="owner-breakdown-track"><div class="owner-breakdown-fill" style="width:${Math.max(3,(Number(r.launches)||0)/max*100)}%"></div></div></div>`).join('')
}
function sessionRow(row,online=false){
  const seen=Math.max(0,Number(row.lastSeenAt||0)-Number(row.startedAt||0));
  const id=String(row.robloxUserId||'');
  const username=String(row.username||'').trim();
  const displayName=String(row.displayName||username||'Unknown user').trim();
  const profile=id?`https://www.roblox.com/users/${encodeURIComponent(id)}/profile`:'#';
  const avatar=safeAvatarUrl(row.avatarUrl);
  const handle=username?`@${username}`:(id?`User ${id}`:'Unknown user');
  const identity=id?`<a class="owner-player owner-session-player" href="${esc(profile)}" target="_blank" rel="noopener noreferrer" title="Open Roblox profile">
    <img class="owner-player-avatar owner-session-avatar" data-owner-avatar src="${esc(avatar)}" alt="" loading="lazy"/>
    <span class="owner-player-copy">
      <span class="owner-player-name">${esc(displayName)}${online?'<span class="owner-online-mini">Online</span>':''}</span>
      <span class="owner-player-handle">${esc(handle)}</span>
    </span>
  </a>`:'<span class="owner-user-id">—</span>';
  return `<tr><td>${identity}</td><td>${esc(gameName(row))}</td><td>${esc(row.device||'unknown')}</td><td>${esc(row.version||'unknown')}</td><td>${esc(executorLabel(row))}</td><td><span class="owner-pill ${row.dashboardLinked?'yes':'no'}">${row.dashboardLinked?'Linked':'No'}</span></td><td>${esc(dateTime(row.startedAt))}</td><td>${esc(online?timeAgo(row.lastSeenAt):duration(seen))}</td></tr>`;
}
function renderTables(a){
  const online=a.onlineSessions||[],recent=a.recent||[],allUsers=a.allUsers||[];
  const visibleUsers=filteredAllUsers(allUsers);
  const filtersActive=Boolean(
    userDirectoryState.query||
    userDirectoryState.online||
    userDirectoryState.dashboard||
    userDirectoryState.today||
    userDirectoryState.device!=='all'
  );

  els.onlineCount.textContent=`${online.length} active ${online.length===1?'session':'sessions'}`;
  els.onlineRows.innerHTML=online.length?online.map(r=>sessionRow(r,true)).join(''):'<tr><td colspan="8" class="muted">No active sessions.</td></tr>';
  els.recentRows.innerHTML=recent.length?recent.map(r=>sessionRow(r,false)).join(''):'<tr><td colspan="8" class="muted">No launch history yet.</td></tr>';

  if(allUsers.length){
    els.allUsersCount.textContent=filtersActive
      ? `${visibleUsers.length} of ${allUsers.length} users shown · first recorded in retained history`
      : `${allUsers.length} unique Roblox ${allUsers.length===1?'user':'users'} · first recorded in retained history`;
  }else{
    els.allUsersCount.textContent='No users in retained history';
  }

  els.allUsers.innerHTML=visibleUsers.map(user=>{
    const row=typeof user==='string'?{userId:user}:user||{};
    const id=String(row.userId||row.robloxUserId||'');
    const username=String(row.username||'').trim();
    const displayName=String(row.displayName||username||'Unknown user').trim();
    const profile=`https://www.roblox.com/users/${encodeURIComponent(id)}/profile`;
    const avatar=safeAvatarUrl(row.avatarUrl);
    const handle=username?`@${username}`:`User ${id}`;
    const device=String(row.device||'unknown').toLowerCase();
    return `<tr>
      <td>
        <a class="owner-player" href="${esc(profile)}" target="_blank" rel="noopener noreferrer" title="Open Roblox profile">
          <img class="owner-player-avatar" data-owner-avatar src="${esc(avatar)}" alt="" loading="lazy"/>
          <span class="owner-player-copy">
            <span class="owner-player-name">${esc(displayName)}${row.online?'<span class="owner-online-mini">Online</span>':''}</span>
            <span class="owner-player-handle">${esc(handle)}</span>
          </span>
        </a>
      </td>
      <td><a class="owner-user-link owner-user-id" href="${esc(profile)}" target="_blank" rel="noopener noreferrer">${esc(id)}</a></td>
      <td><span class="owner-device-pill">${esc(device)}</span></td>
      <td>${esc(executorLabel(row))}</td>
      <td><span class="owner-pill ${row.dashboardLinked?'yes':'no'}">${row.dashboardLinked?'Linked':'No'}</span></td>
      <td>${esc(dateTime(row.firstSeenAt))}</td>
    </tr>`;
  }).join('');

  if(els.allUsersEmpty){
    els.allUsersEmpty.textContent=allUsers.length&&filtersActive?'No users match these filters.':'No users recorded yet.';
    els.allUsersEmpty.hidden=visibleUsers.length>0;
  }
}
function render(a){
  renderMetrics(a);renderLineChart(els.concurrent,a.timeline||[]);renderLaunchChart(els.launches,a.timeline||[]);renderHourly(a.hourly||[]);renderActivityWindows(a);renderPeakRecords(a);renderMilestones(a);renderScriptBlox(a);renderBreakdown(els.versions,a.versions);renderBreakdown(els.games,a.games);renderBreakdown(els.places,a.places);renderBreakdown(els.devices,a.devices);renderBreakdown(els.executors,a.executors);renderTables(a);
  const o=a.online||{};els.liveSummary.textContent=`${num(o.scriptSessions)} sessions · ${num(o.scriptUsers)} unique users · ${num(o.dashboardUsers)} dashboard linked`;els.updated.textContent=`Updated ${new Date(a.generatedAt||Date.now()).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit',second:'2-digit'})}`;
}

function rerenderUserDirectory(){
  if(lastData)renderTables(lastData);
}
els.userSearch?.addEventListener('input',event=>{
  userDirectoryState.query=event.target.value||'';
  rerenderUserDirectory();
});
for(const button of els.userFilters){
  button.addEventListener('click',()=>{
    const key=button.dataset.userFilter;
    if(!key||!(key in userDirectoryState))return;
    userDirectoryState[key]=!userDirectoryState[key];
    button.setAttribute('aria-pressed',String(userDirectoryState[key]));
    rerenderUserDirectory();
  });
}
els.deviceFilter?.addEventListener('click',event=>{
  const button=event.target.closest('[data-device]');
  if(!button)return;
  userDirectoryState.device=button.dataset.device||'all';
  els.deviceFilter.querySelectorAll('[data-device]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));
  rerenderUserDirectory();
});

els.login?.addEventListener('click',()=>authService.login('/admin/'));
els.refresh?.addEventListener('click',fetchAnalytics);
els.range?.addEventListener('click',event=>{const button=event.target.closest('[data-range]');if(!button)return;range=button.dataset.range||'24h';els.range.querySelectorAll('[data-range]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));fetchAnalytics()});
document.addEventListener('visibilitychange',()=>{if(document.hidden){clearTimeout(refreshTimer)}else if(!userPaused)fetchAnalytics()});
window.addEventListener('pagehide',()=>clearTimeout(refreshTimer));
const pauseButton=document.querySelector('#ownerPause');
pauseButton?.addEventListener('click',()=>{userPaused=!userPaused;pauseButton.setAttribute('aria-pressed',String(userPaused));pauseButton.textContent=userPaused?'Resume updates':'Pause updates';if(userPaused)clearTimeout(refreshTimer);else fetchAnalytics();});
window.addEventListener('aroyn:auth-logout',()=>{lastData=null;clearTimeout(refreshTimer);showGate('Signed out. Sign in to view owner analytics.',{login:true});els.allUsers.replaceChildren();els.onlineRows.replaceChildren();els.recentRows.replaceChildren();});

const auth=await authService.init();
if(auth.status!=='authenticated'||!auth.token){showGate('Sign in with your Aroyn Discord account to open the private analytics dashboard.',{login:true})}else{showGate('Verifying owner access…');fetchAnalytics()}

import { initPage, escapeHTML } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
initPage('activity','Activity');
const list=document.querySelector('[data-activity-full]');
function render(s){const source=document.querySelector('[data-activity-source]');if(source)source.textContent=s.live?'Runtime events':'Local events';const items=s.activity||[];list.innerHTML=items.length?items.map(e=>`<div class="event-row"><span class="event-time">${escapeHTML(e.time)}</span><span class="event-marker ${escapeHTML(e.kind)}"></span><div><div class="event-title">${escapeHTML(e.title)}</div><div class="event-detail">${escapeHTML(e.detail||'')}</div></div></div>`).join(''):`<div class="empty-state"><div class="empty-state-inner"><h3>No activity yet</h3><p>No runtime events have been received in this session.</p></div></div>`}
render(runtimeService.getSnapshot());runtimeService.subscribe(render);

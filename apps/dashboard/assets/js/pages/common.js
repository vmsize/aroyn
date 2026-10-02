import { beginPage } from '../core/page-lifecycle.js';
export { subscribePage, pageCallback } from '../core/page-lifecycle.js';
import { mountDashboardShell, setActiveNav } from '../components/shell.js';
import { runtimeService } from '../services/runtime-service.js';
export function initPage(active,title){beginPage();document.title=`Aroyn — ${title}`;mountDashboardShell(active);setActiveNav(active);return runtimeService.getSnapshot()}
export function statusHTML(state,label){const safeState=['connected','disconnected','running','paused','success','warning','error','info','idle'].includes(state)?state:'idle';return `<span class="status ${safeState}"><span class="status-dot"></span><span>${escapeHTML(label)}</span></span>`}
export function escapeHTML(s){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#039;','"':'&quot;'}[c]))}

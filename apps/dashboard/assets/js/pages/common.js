import { mountDashboardShell, setActiveNav } from '../components/shell.js';
import { runtimeService } from '../services/runtime-service.js';
export function initPage(active,title){document.title=`Aroyn — ${title}`;mountDashboardShell(active);setActiveNav(active);return runtimeService.getSnapshot()}
export function statusHTML(state,label){return `<span class="status ${state}"><span class="status-dot"></span><span>${label}</span></span>`}
export function escapeHTML(s){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#039;','"':'&quot;'}[c]))}

import {API_BASE, LIVE_BASE} from '../core/config.js';
import {initSystemTheme, getTheme, resolveMode} from '../core/theme.js';
import {checkHealth} from '../services/service-health.js';
initSystemTheme();
const theme=getTheme();
document.documentElement.dataset.theme=resolveMode(theme.mode);
document.documentElement.dataset.accent=theme.accent;
const $ = name => document.querySelector(`[data-status-${name}]`);
let inFlight = false, timer, disposed = false;
function schedule() {clearTimeout(timer);if (!document.hidden && !disposed) timer = setTimeout(refresh, 60000);}
async function refresh() {
  if (inFlight || document.hidden || disposed) return;
  inFlight = true; $('refresh').disabled = true; $('summary').textContent = 'Checking services…';
  const services = [['api', `${API_BASE.replace(/\/+$/, '')}/api/v1/health`], ['live', `${LIVE_BASE.replace(/\/+$/, '')}/health`]];
  try {
    const results = await Promise.all(services.map(async ([name,url]) => {
      const result = await checkHealth(url);
      if (disposed) return result;
      $(name).textContent = result.responding ? 'Responding' : 'Check unsuccessful';
      $(`${name}-time`).textContent = result.responding ? `${result.durationMs} ms from this browser` : result.reason;
      return result;
    }));
    if (!disposed) {
      $('summary').textContent = results.every(r => r.responding) ? 'Both health endpoints respond' : 'Some checks could not be completed';
      $('updated').textContent = `Last checked ${new Date().toLocaleString()}. Updates every minute while visible.`;
    }
  } finally {inFlight = false; $('refresh').disabled = false; schedule();}
}
$('refresh').addEventListener('click', refresh);
document.addEventListener('visibilitychange', () => {if (document.hidden) clearTimeout(timer);else refresh();});
window.addEventListener('pagehide', () => {disposed = true;clearTimeout(timer);});
window.addEventListener('pageshow', () => {disposed = false;refresh();});
refresh();

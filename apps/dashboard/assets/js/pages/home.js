import { initSystemTheme } from '../core/theme.js';
import { mountAroynField } from '../effects/aroyn-field.js';

document.title = 'Aroyn — Home';
initSystemTheme();

const patternRoot = document.querySelector('#aroyn-field-root');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const background = patternRoot && mountAroynField(patternRoot, {
  variant: 'ascii', cellSize: 16, brightness: .88,
  waveDensity: 1.6, motionSpeed: 1, introDuration: .8,
  paused: reducedMotion.matches,
});
const motionButton = document.querySelector('[data-background-motion]');
let userPaused = false;
function syncBackgroundMotion() {
  const paused = userPaused || reducedMotion.matches;
  background?.setPaused?.(paused);
  if (motionButton) {
    motionButton.hidden = !background?.setPaused;
    motionButton.disabled = reducedMotion.matches;
    motionButton.setAttribute('aria-pressed', String(paused));
    motionButton.textContent = reducedMotion.matches ? 'Background paused' : paused ? 'Resume background' : 'Pause background';
    motionButton.title = reducedMotion.matches ? 'Reduced motion is enabled in your system settings.' : '';
  }
}
motionButton?.addEventListener('click', () => {
  userPaused = !userPaused;
  syncBackgroundMotion();
});
reducedMotion.addEventListener('change', syncBackgroundMotion);
syncBackgroundMotion();
window.addEventListener('pagehide', event => {
  if (!event.persisted) background?.destroy();
});


requestAnimationFrame(() => {
  document.querySelector('.app-splash')?.classList.add('is-hidden');
});

setTimeout(() => {
  document.querySelector('.app-splash')?.remove();
}, 220);



// Browsers may restore the homepage from the back/forward cache (bfcache)
// exactly as it looked at the moment we navigated away. That means the
// "leaving" state and the top route bar can otherwise remain stuck after
// pressing Back from the dashboard.
function restoreHomeAfterHistoryNavigation() {
  if (document.body) {
    delete document.body.dataset.dashboardLeaving;
  }

  const progress = document.querySelector('.route-progress');
  if (progress) {
    progress.classList.remove('is-active', 'is-done');
    progress.style.width = '';
    progress.style.opacity = '';
  }
}

restoreHomeAfterHistoryNavigation();

window.addEventListener('pageshow', () => {
  restoreHomeAfterHistoryNavigation();

  // Force one clean paint after a bfcache restore.
  requestAnimationFrame(() => {
    document.documentElement.getBoundingClientRect();
  });
});

// Smooth handoff to the dashboard.
document.addEventListener('click', event => {
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  ) return;

  const link = event.target.closest?.('a[href]');
  if (!link || link.target === '_blank' || link.hasAttribute('download')) return;

  const target = new URL(link.href, location.href);
  if (target.origin !== location.origin || !target.pathname.startsWith('/dashboard/')) return;

  event.preventDefault();

  try {
    sessionStorage.setItem('veyra.fromHome', '1');
  } catch {}

  const progress = document.querySelector('.route-progress');
  progress?.classList.remove('is-done');
  progress?.classList.add('is-active');

  document.body.dataset.dashboardLeaving = 'true';

  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  setTimeout(() => {
    location.href = target.href;
  }, reduce ? 0 : 175);
});

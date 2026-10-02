let currentPage = null;

export function disposePage() {
  const page = currentPage;
  currentPage = null;
  if (!page) return;
  page.active = false;
  for (const cleanup of page.cleanups) cleanup();
  page.cleanups.clear();
}

export function beginPage() {
  disposePage();
  currentPage = { active: true, cleanups: new Set() };
}

export function pageCallback(callback) {
  const page = currentPage;
  if (!page) throw new Error('Page lifecycle has not started.');
  return (...args) => { if (page.active) return callback(...args); };
}

export function subscribePage(service, callback) {
  const page = currentPage;
  const unsubscribe = service.subscribe(pageCallback(callback));
  const cleanup = () => { unsubscribe(); page.cleanups.delete(cleanup); };
  page.cleanups.add(cleanup);
  return cleanup;
}

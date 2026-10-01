export async function checkHealth(url, {fetcher = globalThis.fetch, timeoutMs = 8000} = {}) {
  const controller = new AbortController();
  const started = Date.now();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetcher(url, {method:'GET', credentials:'omit', cache:'no-store', referrerPolicy:'no-referrer', headers:{Accept:'application/json'}, signal:controller.signal});
    if (!response.ok) return {responding:false, reason:`HTTP ${response.status}`};
    const body = await response.json();
    if (body?.ok !== true) return {responding:false, reason:'Unexpected response'};
    return {responding:true, durationMs:Date.now() - started};
  } catch { return {responding:false, reason:controller.signal.aborted ? 'Timed out' : 'Could not check'}; }
  finally { clearTimeout(timer); }
}

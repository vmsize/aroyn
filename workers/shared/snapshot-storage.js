const runtimeKey = key => /^runtime-v[123]\//.test(String(key));
async function boundedBody(request) {
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks = []; let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 300 * 1024) { await reader.cancel(); throw new Error('Snapshot storage payload too large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

// All mutations of a runtime object use the same per-key Durable Object.
// Reads/listing stay on R2. No telemetry or queue state is persisted in the DO.
export function withSnapshotStorage(env) {
  if (env.PAYLOADS?.aroynCoordinated) return env;
  const bucket = env.PAYLOADS;
  async function mutate(key, operation, value = null, options = {}) {
    if (!env.SNAPSHOT_STORAGE) throw new Error('Snapshot coordination binding unavailable');
    const stub = env.SNAPSHOT_STORAGE.get(env.SNAPSHOT_STORAGE.idFromName(key));
    const response = await stub.fetch('https://internal/' + operation, {
      method: 'POST', headers: {'x-object-key': key, 'x-options': JSON.stringify(options)}, body: value,
    });
    if (!response.ok) throw new Error('Snapshot storage operation failed');
    return response.json();
  }
  return {...env, PAYLOADS: {
    aroynCoordinated: true,
    list: options => bucket.list(options), head: key => bucket.head(key), get: (key, options) => bucket.get(key, options),
    put: (key, value, options) => runtimeKey(key) ? mutate(key, 'put', value, options) : bucket.put(key, value, options),
    async delete(keys) {
      for (const key of Array.isArray(keys) ? keys : [keys]) {
        if (runtimeKey(key)) await mutate(key, 'delete'); else await bucket.delete(key);
      }
    },
    async expire(key, etag, cutoff) {
      return (await mutate(key, 'expire', null, {etag, cutoff})).removed === true;
    },
  }};
}

export class AroynSnapshotStore {
  constructor(ctx, env) { this.env = env; this.tail = Promise.resolve(); }

  async fetch(request) {
    const key = request.headers.get('x-object-key');
    const operation = new URL(request.url).pathname;
    if (request.method !== 'POST' || !runtimeKey(key) || key.length > 512 || !['/put', '/delete', '/expire'].includes(operation)) {
      return new Response('Invalid storage operation', {status: 400});
    }
    const options = JSON.parse(request.headers.get('x-options') || '{}');
    // Queue immediately, before any R2 await; other requests cannot slip between
    // the expiry head check and deletion. Awaited requests keep the instance alive.
    const task = this.tail.then(async () => {
      const bucket = this.env.PAYLOADS;
      if (operation === '/put') {
        await bucket.put(key, await boundedBody(request), options);
        return Response.json({ok: true});
      }
      if (operation === '/delete') {
        await bucket.delete(key);
        return Response.json({ok: true});
      }
      if (!Number.isFinite(options.cutoff) || typeof options.etag !== 'string') return new Response('Invalid expiry condition', {status: 400});
      const current = await bucket.head(key);
      if (!current || current.etag !== options.etag || current.uploaded.getTime() >= options.cutoff || key.includes('/revoked/')) {
        return Response.json({removed: false});
      }
      await bucket.delete(key);
      return Response.json({removed: true});
    });
    this.tail = task.then(() => undefined, () => undefined);
    return task;
  }
}

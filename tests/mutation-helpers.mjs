import {AroynRuntimeMutations} from '../workers/api/src/worker.js';

// The real coordinator class with the caller's injected local bindings. Native
// Miniflare namespaces retain their own env and cannot see per-test R2 faults.
export function localMutationNamespace(env) {
  const instances = new Map();
  return {
    idFromName: id => id,
    get(id) {
      if (!instances.has(id)) instances.set(id, new AroynRuntimeMutations({id: {name: id}}, env));
      return {fetch: (input, options) => instances.get(id).fetch(input instanceof Request ? input : new Request(input, options))};
    },
  };
}

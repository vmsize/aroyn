const encoder = new TextEncoder();
const MAX_BYTES = 256 * 1024;

// Per socket, bounded ephemeral state. A missing part expires and the next
// complete snapshot replaces it; partial counters are never displayed.
export class LiveSnapshotAssembler {
  constructor() { this.pending = null; this.completedId = null; }

  accept(message, selected, now = Date.now()) {
    if (message?.type !== 'snapshot' || String(message.player?.userId || '') !== selected) return null;
    const t = message.transport;
    if (t == null) { this.pending = null; return message; }
    if (t.encoding !== 'json-fragments-v1' || !/^[A-Za-z0-9_-]{8,64}$/.test(String(t.id || '')) ||
        !Number.isInteger(t.count) || t.count < 1 || t.count > 16 ||
        !Number.isInteger(t.index) || t.index < 1 || t.index > t.count ||
        !Number.isInteger(t.bytes) || t.bytes < 1 || t.bytes > MAX_BYTES ||
        typeof t.data !== 'string' || encoder.encode(t.data).byteLength > 32 * 1024) return null;
    if (t.id === this.completedId) return null;
    if (!this.pending || this.pending.id !== t.id || now - this.pending.startedAt > 15000) {
      this.pending = {id:t.id, count:t.count, expectedBytes:t.bytes, sessionId:message.session?.id,
        startedAt:now, parts:new Map(), receivedBytes:0};
    }
    const p = this.pending;
    if (p.count !== t.count || p.expectedBytes !== t.bytes || p.sessionId !== message.session?.id) {
      this.pending = null; return null;
    }
    if (p.parts.has(t.index)) {
      if (p.parts.get(t.index) !== t.data) this.pending = null;
      return null;
    }
    p.receivedBytes += encoder.encode(t.data).byteLength;
    if (p.receivedBytes > p.expectedBytes) { this.pending = null; return null; }
    p.parts.set(t.index,t.data);
    if (p.parts.size !== p.count) return null;
    this.pending = null;
    if (p.receivedBytes !== p.expectedBytes) return null;
    const text = Array.from({length:p.count},(_,i)=>p.parts.get(i+1)).join('');
    let snapshot;
    try { snapshot = JSON.parse(text); } catch { return null; }
    if (snapshot?.type !== 'snapshot' || snapshot.schemaVersion !== 1 || snapshot.transport != null ||
        String(snapshot.player?.userId || '') !== selected || snapshot.session?.id !== p.sessionId) return null;
    this.completedId = p.id;
    return snapshot;
  }
}

export function transportLabel(snapshot){
  if(snapshot?.bridge?.liveTransport==='connected')return 'WebSocket';
  if(!snapshot?.live)return 'Not connected';
  const base=snapshot?.bridge?.apiBase||'';
  if(base.startsWith('https://'))return 'HTTPS telemetry / polling';
  if(base.startsWith('http://'))return 'HTTP telemetry / polling';
  return 'Telemetry polling';
}

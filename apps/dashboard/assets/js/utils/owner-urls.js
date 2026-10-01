export function safeAvatarUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && !url.username && !url.password && !url.port
        && (url.hostname === 'rbxcdn.com' || url.hostname.endsWith('.rbxcdn.com'))) return url.href;
  } catch {}
  return '/assets/aroyn-mark.png';
}
export function safeScriptBloxUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && url.hostname === 'scriptblox.com' && !url.username && !url.password && !url.port && url.pathname.startsWith('/script/')) return url.href;
  } catch {}
  return '';
}

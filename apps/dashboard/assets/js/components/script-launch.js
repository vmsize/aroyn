export function launchCommand(loaderUrl) {
  if (!loaderUrl) return '';
  let url;
  try { url = new URL(loaderUrl); } catch { return ''; }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash
      || !url.pathname.endsWith('/loader.luau') || !/^[\x21-\x7e]+$/.test(url.href)) return '';
  return `loadstring(game:HttpGet(${JSON.stringify(url.href)}))()`;
}

export function mountScriptLaunch(root, loaderUrl, clipboard = globalThis.navigator?.clipboard) {
  if (!root) return;
  const command = launchCommand(loaderUrl);
  root.hidden = !command;
  if (!command) return;
  const button = root.querySelector('[data-copy-script]');
  const status = root.ownerDocument?.querySelector('[data-copy-status]') || root.querySelector('[data-copy-status]');
  const field = root.querySelector('[data-launch-command]');
  const manual = root.querySelector('[data-manual-copy]');
  field.value = command;
  let copying = false;
  let dismissTimer;
  function announce(message) {
    clearTimeout(dismissTimer);
    status.textContent = message;
    status.classList.add('is-visible');
    dismissTimer = setTimeout(() => status.classList.remove('is-visible'), 3000);
  }
  async function copy() {
    if (copying) return;
    copying = true;
    button.disabled = true;
    try {
      if (!clipboard?.writeText) throw new Error('Clipboard unavailable');
      await clipboard.writeText(command);
      manual.hidden = true;
      announce('Script copied');
    } catch {
      manual.hidden = false;
      field.focus();
      field.select();
      announce('Copy the selected command manually.');
    } finally { copying = false; button.disabled = false; }
  }
  button.addEventListener('click', copy);
}

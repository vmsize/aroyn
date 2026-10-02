const focusable = 'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), [tabindex="0"]';

export function preservePanelFocus(panel, update, fallback = null) {
  const active = document.activeElement;
  const heldFocus = panel.contains(active);
  const key = active?.getAttribute('data-focus-key');
  update();
  if (heldFocus && panel.dataset.open === 'true') {
    const replacement = key ? panel.querySelector(`[data-focus-key=${JSON.stringify(key)}]`) : null;
    const next = replacement && !replacement.disabled ? replacement : fallback?.() || panel.querySelector(focusable) || panel;
    next.focus({ preventScroll: true });
  }
}

export function mountDisclosure({ trigger, panel, id, initialFocus = null }) {
  panel.id = id;
  panel.tabIndex = -1;
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-modal', 'false');
  trigger.setAttribute('aria-controls', id);
  trigger.setAttribute('aria-haspopup', 'dialog');
  const isOpen = () => panel.dataset.open === 'true';
  const setOpen = (open, { focus = open, returnFocus = false } = {}) => {
    if (!open && (returnFocus || panel.contains(document.activeElement))) trigger.focus({ preventScroll: true });
    panel.dataset.open = String(open);
    panel.toggleAttribute('inert', !open);
    panel.setAttribute('aria-hidden', String(!open));
    trigger.setAttribute('aria-expanded', String(open));
    if (open && focus) (initialFocus?.() || panel.querySelector(focusable) || panel).focus({ preventScroll: true });
  };
  setOpen(false);
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && isOpen()) { event.preventDefault(); setOpen(false, { returnFocus: true }); }
  });
  document.addEventListener('focusin', event => {
    if (isOpen() && !panel.contains(event.target) && !trigger.contains(event.target)) setOpen(false);
  });
  return { isOpen, setOpen, open: () => setOpen(true), close: () => setOpen(false) };
}

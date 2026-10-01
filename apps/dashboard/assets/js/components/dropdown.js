const chevron = `<svg class="dropdown-chevron" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m7 9.5 5 5 5-5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

export function mountAnimatedDropdown(root, { value, options = [], onChange } = {}) {
  if (!root) return null;
  root.classList.add('animated-dropdown');
  root.innerHTML = `
    <button class="animated-dropdown-trigger" type="button" aria-haspopup="listbox" aria-expanded="false">
      <span class="animated-dropdown-value"></span>${chevron}
    </button>
    <div class="animated-dropdown-menu" role="listbox"></div>`;

  const trigger = root.querySelector('.animated-dropdown-trigger');
  const valueEl = root.querySelector('.animated-dropdown-value');
  const menu = root.querySelector('.animated-dropdown-menu');
  const label = root.closest('.setting-row')?.querySelector('.setting-name')?.textContent?.trim()
    || root.getAttribute('aria-label') || 'Select an option';
  trigger.setAttribute('aria-label', label);
  menu.setAttribute('aria-label', label);
  let current = value ?? options[0]?.value ?? '';
  let open = false;

  const getLabel = () => options.find(x => x.value === current)?.label ?? String(current);

  function renderValue() {
    valueEl.textContent = getLabel();
    root.dataset.value = current;
    menu.querySelectorAll('[role="option"]').forEach(item => {
      const selected = item.dataset.value === String(current);
      item.setAttribute('aria-selected', String(selected));
    });
  }

  function setOpen(next, { focus = false } = {}) {
    open = !!next;
    root.dataset.open = String(open);
    trigger.setAttribute('aria-expanded', String(open));
    menu.querySelectorAll('[role="option"]').forEach(item => {
      item.tabIndex = open && item.dataset.value === String(current) ? 0 : -1;
    });
    if (open && focus) requestAnimationFrame(() => {
      if (open) menu.querySelector('[aria-selected="true"]')?.focus();
    });
  }

  options.forEach((option, index) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'animated-dropdown-item';
    item.role = 'option';
    item.tabIndex = -1;
    item.dataset.value = option.value;
    item.style.setProperty('--item-index', index);
    item.innerHTML = `<span>${option.label}</span><span class="dropdown-check" aria-hidden="true">✓</span>`;
    item.addEventListener('click', () => {
      current = option.value;
      renderValue();
      setOpen(false);
      trigger.focus();
      onChange?.(current);
    });
    menu.append(item);
  });

  trigger.addEventListener('click', () => setOpen(!open));
  trigger.addEventListener('keydown', e => {
    if ((e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === ' ') && !open) {
      e.preventDefault();
      setOpen(true, { focus: true });
    }
  });
  menu.addEventListener('keydown', e => {
    const items = [...menu.querySelectorAll('.animated-dropdown-item')];
    const index = items.indexOf(document.activeElement);
    if (e.key === 'Escape') {
      e.preventDefault();
      setOpen(false);
      trigger.focus();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      items[(index + 1 + items.length) % items.length]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      items[(index - 1 + items.length) % items.length]?.focus();
    } else if (e.key === 'Home' || e.key === 'End') {
      e.preventDefault();
      items[e.key === 'Home' ? 0 : items.length - 1]?.focus();
    }
  });

  const outside = e => {
    if (open && !root.contains(e.target)) setOpen(false);
  };
  document.addEventListener('pointerdown', outside);
  root.addEventListener('focusout', e => {
    // A pointer click moves focus from the trigger to an option before click.
    // activeElement can still be body during focusout; trust the destination
    // so the menu is not hidden before the option receives its click.
    if (e.relatedTarget) {
      if (!root.contains(e.relatedTarget)) setOpen(false);
      return;
    }
    requestAnimationFrame(() => {
      if (!root.contains(document.activeElement)) setOpen(false);
    });
  });

  renderValue();

  return {
    get value() { return current; },
    setValue(next) { current = next; renderValue(); },
    destroy() { document.removeEventListener('pointerdown', outside); },
  };
}

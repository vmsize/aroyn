import { getTheme, applyTheme, toggleThemeAnimated } from '../core/theme.js';
import { icons } from '../core/icons.js';
const accentMeta={mono:['Mono','#9a9a96'],graphite:['Graphite','#7f8791'],slate:['Slate','#8798aa'],steel:['Steel','#94a3b8'],arctic:['Arctic','#79a7b4'],sage:['Sage','#879c88'],sand:['Sand','#ae9a78']};

export function mountSettings(){
  const trigger=document.querySelector('[data-settings-trigger]');
  if(!trigger)return;
  const existing=document.querySelector('.settings-panel');
  if(existing)return existing;

  const panel=document.createElement('section');
  panel.className='settings-panel';panel.dataset.open='false';
  panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','false');panel.setAttribute('aria-label','Settings');
  panel.innerHTML=`
    <div class="settings-head"><h2>Settings</h2></div>
    <div class="settings-body">
      <div class="settings-section">
        <div class="settings-label">Appearance</div>
        <div class="appearance-row">
          <div><div class="appearance-name">Theme</div><div class="appearance-value" data-theme-label>Dark</div></div>
          <button class="theme-toggle" type="button" data-theme-toggle aria-label="Toggle light and dark theme"></button>
        </div>
        <div class="appearance-row system-row">
          <div><div class="appearance-name">Follow system</div><div class="appearance-help">Use the browser color scheme automatically.</div></div>
          <button class="switch" type="button" role="switch" data-system-theme aria-label="Follow system theme"></button>
        </div>
      </div>
      <div class="settings-section"><div class="settings-label">Color theme</div><div class="accent-grid" data-accent-options></div></div>
      <div class="settings-section"><div class="field-help">Preferences are stored locally in this browser and apply on direct dashboard visits.</div></div>
    </div>`;
  document.body.append(panel);

  const themeButton=panel.querySelector('[data-theme-toggle]');
  const systemButton=panel.querySelector('[data-system-theme]');
  const themeLabel=panel.querySelector('[data-theme-label]');
  const accentWrap=panel.querySelector('[data-accent-options]');

  Object.entries(accentMeta).forEach(([k,[label,color]])=>{const b=document.createElement('button');b.className='accent-option';b.type='button';b.dataset.accent=k;b.innerHTML=`<span class="swatch" style="--swatch:${color}"></span><span>${label}</span>`;b.addEventListener('click',()=>{const t=getTheme();applyTheme(t.mode,k);sync()});accentWrap.append(b)});

  async function toggleTheme(){await toggleThemeAnimated(themeButton);sync()}
  themeButton.addEventListener('click',toggleTheme);
  systemButton.addEventListener('click',()=>{const t=getTheme();const next=t.mode==='system'?(document.documentElement.dataset.theme||'dark'):'system';applyTheme(next,t.accent);sync()});

  function sync(){
    const t=getTheme();const resolved=document.documentElement.dataset.theme||'dark';
    themeLabel.textContent=t.mode==='system'?`System · ${resolved[0].toUpperCase()+resolved.slice(1)}`:resolved[0].toUpperCase()+resolved.slice(1);
    themeButton.innerHTML=resolved==='dark'?icons.sun:icons.moon;
    themeButton.setAttribute('aria-label',resolved==='dark'?'Switch to light theme':'Switch to dark theme');
    systemButton.setAttribute('aria-checked',String(t.mode==='system'));
    panel.querySelectorAll('[data-accent]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.accent===t.accent)));
  }
  sync();
  window.addEventListener('aroyn:theme',sync);

  const setOpen=v=>{panel.dataset.open=String(v);trigger.setAttribute('aria-expanded',String(v));};
  trigger.addEventListener('click',e=>{e.stopPropagation();setOpen(panel.dataset.open!=='true')});
  document.addEventListener('click',e=>{if(panel.dataset.open==='true'&&!panel.contains(e.target)&&!trigger.contains(e.target))setOpen(false)},true);
  document.addEventListener('keydown',e=>{if(e.key==='Escape'&&panel.dataset.open==='true'){setOpen(false);trigger.focus()}});
  return panel;
}

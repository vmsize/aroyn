import { initPage } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
import { storage } from '../core/storage.js';
import { toast } from '../core/toast.js';
import { mountAnimatedDropdown } from '../components/dropdown.js';

const state=initPage('configuration','Configuration');
const defaults={...state.config};
const stored={...storage.get('runtime.config',{})};
delete stored.pollingInterval;
delete stored.reconnectInterval;
const cfg={...defaults,...stored};
const dropdowns=new Map();

function syncSwitches(){
  document.querySelectorAll('[data-switch]').forEach(b=>{
    const k=b.dataset.switch;
    b.setAttribute('aria-checked',String(!!cfg[k]));
  });
}

function syncInputs(){
  document.querySelectorAll('input[data-config]').forEach(el=>{
    const k=el.dataset.config;
    el.value=cfg[k] ?? '';
  });
  dropdowns.forEach((dropdown,key)=>dropdown.setValue(cfg[key]));
}

document.querySelectorAll('[data-switch]').forEach(b=>{
  const k=b.dataset.switch;
  b.setAttribute('aria-checked',String(!!cfg[k]));
  b.addEventListener('click',()=>{
    cfg[k]=b.getAttribute('aria-checked')!=='true';
    b.setAttribute('aria-checked',String(cfg[k]));
    runtimeService.updateConfig({[k]:cfg[k]});
  });
});

document.querySelectorAll('input[data-config]').forEach(el=>{
  const k=el.dataset.config;
  el.value=cfg[k] ?? '';
  el.addEventListener('change',()=>{
    const v=el.type==='number'?Number(el.value):el.value;
    cfg[k]=v;
    runtimeService.updateConfig({[k]:v});
  });
});

document.querySelectorAll('.animated-select[data-config]').forEach(root=>{
  const key=root.dataset.config;
  const options=(root.dataset.options||'').split('|').filter(Boolean).map(pair=>{
    const [value,label]=pair.split('::');return {value,label};
  });
  const dropdown=mountAnimatedDropdown(root,{value:cfg[key],options,onChange(value){cfg[key]=value;runtimeService.updateConfig({[key]:value})}});
  dropdowns.set(key,dropdown);
});

document.querySelector('[data-save]')?.addEventListener('click',()=>{
  storage.set('runtime.config',cfg);
  toast('Configuration saved','Stored locally in this browser.','success');
});

document.querySelector('[data-reset]')?.addEventListener('click',()=>{
  Object.keys(cfg).forEach(k=>delete cfg[k]);
  Object.assign(cfg,defaults);
  localStorage.removeItem('veyra.runtime.config');
  runtimeService.updateConfig({...cfg});
  syncSwitches();syncInputs();
  toast('Configuration reset','Local changes were reset without reloading the dashboard.','success');
});

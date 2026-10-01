
let region;
export function initToasts(){region=document.querySelector('.toast-region');if(!region){region=document.createElement('div');region.className='toast-region';region.setAttribute('aria-live','polite');document.body.append(region)}}
export function toast(title,copy='',type='default'){if(!region)initToasts();const el=document.createElement('div');el.className=`toast ${type==='danger'?'is-danger':type==='success'?'is-success':''}`;el.innerHTML=`<span class="toast-mark"></span><div><div class="toast-title"></div><div class="toast-copy"></div></div>`;el.querySelector('.toast-title').textContent=title;el.querySelector('.toast-copy').textContent=copy;region.append(el);setTimeout(()=>el.remove(),3600)}

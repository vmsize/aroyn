import { storage } from './storage.js';
const accents=['mono','graphite','slate','steel','arctic','sage','sand'];
const modes=['dark','light','system'];
let media=matchMedia('(prefers-color-scheme: light)');
export function getTheme(){return {mode:storage.getRaw('theme.mode','dark'),accent:storage.getRaw('theme.accent','steel')}}
export function resolveMode(mode){return mode==='system'?(media.matches?'light':'dark'):mode}
export function applyTheme(mode,accent){if(!modes.includes(mode))mode='dark';if(!accents.includes(accent))accent='steel';const resolved=resolveMode(mode);document.documentElement.dataset.theme=resolved;document.documentElement.dataset.themeMode=mode;document.documentElement.dataset.accent=accent;storage.setRaw('theme.mode',mode);storage.setRaw('theme.accent',accent);window.dispatchEvent(new CustomEvent('aroyn:theme',{detail:{mode,accent,resolved}}));}
export function initSystemTheme(){const handler=()=>{const t=getTheme();if(t.mode==='system')applyTheme(t.mode,t.accent)};media.addEventListener?.('change',handler);return()=>media.removeEventListener?.('change',handler)}
export async function toggleThemeAnimated(origin){
  const current=getTheme();
  const resolved=document.documentElement.dataset.theme||resolveMode(current.mode);
  const next=resolved==='dark'?'light':'dark';
  const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;

  if(origin)origin.classList.add('is-switching');

  if(reduce||typeof document.startViewTransition!=='function'){
    applyTheme(next,current.accent);
    if(origin)requestAnimationFrame(()=>origin.classList.remove('is-switching'));
    return next;
  }

  const rect=origin?.getBoundingClientRect();
  const x=rect?rect.left+rect.width/2:innerWidth/2;
  const y=rect?rect.top+rect.height/2:innerHeight/2;
  const endRadius=Math.hypot(Math.max(x,innerWidth-x),Math.max(y,innerHeight-y));

  const transition=document.startViewTransition(()=>{
    applyTheme(next,current.accent);
  });

  try{
    await transition.ready;
    const animation=document.documentElement.animate(
      {clipPath:[`circle(0px at ${x}px ${y}px)`,`circle(${endRadius}px at ${x}px ${y}px)`]},
      {duration:430,easing:'cubic-bezier(.22,.7,.2,1)',pseudoElement:'::view-transition-new(root)'}
    );
    await animation.finished.catch(()=>{});
  }catch{
    // Theme is already applied if the transition API fails after capture.
  }

  if(origin)origin.classList.remove('is-switching');
  return next;
}

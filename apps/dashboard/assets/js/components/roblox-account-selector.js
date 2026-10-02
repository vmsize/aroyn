import { mountDisclosure, preservePanelFocus } from '../core/disclosure.js';
import { runtimeService } from '../services/runtime-service.js';
import { toast } from '../core/toast.js';

function esc(value){return String(value??'').replace(/[&<>'"]/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[ch]))}
const trashMark=`<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M18 6L17.1991 18.0129C17.129 19.065 17.0939 19.5911 16.8667 19.99C16.6666 20.3412 16.3648 20.6235 16.0011 20.7998C15.588 21 15.0607 21 14.0062 21H9.99377C8.93927 21 8.41202 21 7.99889 20.7998C7.63517 20.6235 7.33339 20.3412 7.13332 19.99C6.90607 19.5911 6.871 19.065 6.80086 18.0129L6 6M4 6H20M16 6L15.7294 5.18807C15.4671 4.40125 15.3359 4.00784 15.0927 3.71698C14.8779 3.46013 14.6021 3.26132 14.2905 3.13878C13.9376 3 13.523 3 12.6936 3H11.3064C10.477 3 10.0624 3 9.70951 3.13878C9.39792 3.26132 9.12208 3.46013 8.90729 3.71698C8.66405 4.00784 8.53292 4.40125 8.27064 5.18807L8 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
function avatar(account,cls='roblox-account-avatar'){
  if(account?.avatarUrl)return`<img class="${cls}" src="${esc(account.avatarUrl)}" alt="" loading="lazy">`;
  const initial=String(account?.displayName||account?.username||'?').trim().slice(0,1).toUpperCase()||'?';
  return`<span class="${cls} roblox-account-avatar-fallback">${esc(initial)}</span>`;
}

export function mountRobloxAccountSelector(){
  const actions=document.querySelector('.header-actions');
  if(!actions||actions.querySelector('[data-roblox-account-selector]'))return;
  const settings=actions.querySelector('[data-settings-trigger]');
  const wrap=document.createElement('div');
  wrap.className='roblox-account-selector';wrap.dataset.robloxAccountSelector='';
  wrap.innerHTML=`<button class="roblox-account-trigger" type="button" aria-expanded="false" data-roblox-account-trigger></button><section class="roblox-account-menu" data-open="false" data-roblox-account-menu aria-label="Roblox accounts"></section>`;
  if(settings)actions.insertBefore(wrap,settings);else actions.append(wrap);
  const trigger=wrap.querySelector('[data-roblox-account-trigger]');
  const menu=wrap.querySelector('[data-roblox-account-menu]');
  const choices=()=>[...menu.querySelectorAll('[data-roblox-user-id]')];
  const disclosure=mountDisclosure({trigger,panel:menu,id:'aroyn-roblox-account-panel',initialFocus:()=>menu.querySelector('[data-roblox-user-id][aria-pressed="true"]')||choices()[0]});
  let lastSnapshot=runtimeService.getSnapshot(),confirmingId=null,removingId=null;
  const close=()=>{disclosure.close();confirmingId=null};
  const open=()=>{confirmingId=null;render(lastSnapshot);disclosure.open()};
  trigger.addEventListener('click',e=>{e.stopPropagation();disclosure.isOpen()?close():open()});
  trigger.addEventListener('keydown',event=>{
    if(!['ArrowDown','ArrowUp'].includes(event.key))return;
    event.preventDefault();open();if(event.key==='ArrowUp')choices().at(-1)?.focus();
  });
  menu.addEventListener('keydown',event=>{
    const buttons=choices();const index=buttons.indexOf(event.target.closest?.('[data-roblox-user-id]'));
    if(index<0||!['ArrowDown','ArrowUp','Home','End'].includes(event.key))return;
    event.preventDefault();const next=event.key==='Home'?0:event.key==='End'?buttons.length-1:(index+(event.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length;
    buttons[next].focus();
  });
  menu.addEventListener('click',async e=>{
    const remove=e.target.closest('[data-remove-roblox-user-id]');
    if(remove){e.stopPropagation();if(removingId)return;confirmingId=String(remove.dataset.removeRobloxUserId||'');render(lastSnapshot);menu.querySelector('[data-remove-cancel]')?.focus();return}
    const cancel=e.target.closest('[data-remove-cancel]');
    if(cancel){e.stopPropagation();const id=confirmingId;confirmingId=null;render(lastSnapshot);menu.querySelector(`[data-focus-key=${JSON.stringify('remove-'+id)}]`)?.focus();return}
    const confirm=e.target.closest('[data-remove-confirm]');
    if(confirm){
      e.stopPropagation();if(removingId)return;
      const id=String(confirm.dataset.removeConfirm||'');const account=(lastSnapshot.bridge?.accounts||[]).find(a=>String(a.userId)===id);
      removingId=id;render(lastSnapshot);
      try{const removed=await runtimeService.removeRobloxAccount(id);if(removed)toast('Roblox account removed',`${account?.username||account?.displayName||'Account'} must be linked again from Aroyn Hub → Session.`,'success');confirmingId=null}
      catch(err){toast('Remove account failed',err instanceof Error?err.message:String(err),'danger')}
      finally{removingId=null;render(lastSnapshot)}
      return;
    }
    const choice=e.target.closest('[data-roblox-user-id]');if(!choice)return;
    const pending=runtimeService.selectRobloxAccount(choice.dataset.robloxUserId);close();
    try{await pending}catch(err){toast('Account switch failed',err instanceof Error?err.message:String(err),'danger')}
  });
  document.addEventListener('click',e=>{if(disclosure.isOpen()&&!wrap.contains(e.target))close()},true);

  function render(s){
    lastSnapshot=s;
    preservePanelFocus(menu,()=>{
      const accounts=s.bridge?.accounts||[],accountsLoaded=s.bridge?.accountsLoaded===true;
      const selectedId=String(s.bridge?.selectedRobloxUserId||'');
      const selected=accounts.find(a=>String(a.userId)===selectedId)||accounts[0]||null;
      const chevron='<svg class="roblox-account-chevron" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="m6 8 4 4 4-4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      if(selected){
        trigger.innerHTML=`${avatar(selected)}<span class="roblox-account-trigger-copy"><strong>${esc(selected.displayName||selected.username)}</strong><span>@${esc(selected.username)} · ${esc(selected.userId)}</span></span>${chevron}`;
        trigger.title=`Roblox account: ${selected.username}`;
      }else{
        trigger.innerHTML=`<span class="roblox-account-avatar roblox-account-avatar-fallback">R</span><span class="roblox-account-trigger-copy"><strong>${accountsLoaded?'No Roblox account':'Loading accounts'}</strong><span>${accountsLoaded?'Waiting for Aroyn Hub':'Syncing Aroyn runtime…'}</span></span>${chevron}`;
        trigger.title=accountsLoaded?'Roblox accounts':'Loading Roblox accounts';
      }
      let html;
      if(!accountsLoaded){
        html='<div class="roblox-account-menu-head"><strong>Roblox accounts</strong><span>Syncing…</span></div><div class="roblox-account-empty"><strong>Loading accounts…</strong><p>Waiting for the dashboard account list to finish syncing.</p></div>';
      }else if(!accounts.length){
        html='<div class="roblox-account-menu-head"><strong>Roblox accounts</strong><span>0 linked</span></div><div class="roblox-account-empty"><strong>No accounts yet</strong><p>Run Aroyn Hub on a Roblox account using this dashboard key. Each account will appear here automatically.</p></div>';
      }else{
        html=`<div class="roblox-account-menu-head"><strong>Roblox accounts</strong><span>${accounts.length} linked</span></div><div class="roblox-account-list">${accounts.map(account=>{
          const id=String(account.userId),selected=id===selectedId,confirming=id===confirmingId,busy=id===removingId;
          return `<div class="roblox-account-option${selected?' is-selected':''}${confirming?' is-confirming':''}"><button class="roblox-account-select" type="button" aria-pressed="${selected}" data-roblox-user-id="${esc(id)}" data-focus-key="select-${esc(id)}" aria-label="Select ${esc(account.displayName||account.username)} (@${esc(account.username)}), ID ${esc(id)}">${avatar(account,'roblox-account-option-avatar')}<span class="roblox-account-option-copy"><strong>${esc(account.displayName||account.username)}</strong><span>@${esc(account.username)} · ID ${esc(id)}</span></span><span class="roblox-account-state ${account.online?'is-online':'is-offline'}"><span></span>${account.online?'Live':'Offline'}</span></button><button class="roblox-account-remove" type="button" ${removingId?'disabled':''} aria-label="Remove ${esc(account.username)} from Aroyn" title="Remove account" data-remove-roblox-user-id="${esc(id)}" data-focus-key="remove-${esc(id)}">${trashMark}</button>${confirming?`<div class="roblox-account-remove-confirm"><span>Remove this account? It will need to be linked again in Aroyn Hub.</span><div><button class="btn" type="button" data-remove-cancel data-focus-key="cancel-${esc(id)}">Cancel</button><button class="btn btn-danger" type="button" ${busy?'disabled':''} data-remove-confirm="${esc(id)}" data-focus-key="confirm-${esc(id)}">${busy?'Removing…':'Remove'}</button></div></div>`:''}</div>`;
        }).join('')}</div>`;
      }
      if(menu.innerHTML!==html)menu.innerHTML=html;
    },()=>menu.querySelector('[data-remove-cancel]')||menu.querySelector('[data-roblox-user-id][aria-pressed="true"]')||choices()[0]);
  }
  render(lastSnapshot);runtimeService.subscribe(render);
  return {trigger,menu};
}

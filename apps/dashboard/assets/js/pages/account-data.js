import { initPage } from './common.js';
import { authService } from '../services/auth-service.js';

if(!document.querySelector('link[data-account-data-style]')){
  const style=document.createElement('link');style.rel='stylesheet';style.href='/assets/styles/account-data.css';style.dataset.accountDataStyle='';document.head.append(style);
}
initPage('', 'Account data');
const page=document.querySelector('[data-account-data-page]');
const status=page.querySelector('[data-data-status]');
const download=page.querySelector('[data-data-export]');
const open=page.querySelector('[data-delete-open]');
const form=page.querySelector('[data-delete-form]');
const confirmation=page.querySelector('#delete-confirmation');
const remove=page.querySelector('[data-delete-submit]');
const reauth=page.querySelector('[data-data-reauth]');
let available=false,busy=false;
function message(text,error=false){status.textContent=text;status.dataset.error=String(error);status.setAttribute('role',error?'alert':'status')}
function controls(){download.disabled=!available||busy;open.disabled=!available||busy;confirmation.disabled=busy;remove.disabled=!available||busy||confirmation.value!=='DELETE';page.querySelector('[data-delete-cancel]').disabled=busy}
function cancel(){form.hidden=true;confirmation.value='';reauth.hidden=true;controls();open.focus()}
confirmation.addEventListener('input',controls);
open.addEventListener('click',()=>{form.hidden=false;confirmation.focus()});
page.querySelector('[data-delete-cancel]').addEventListener('click',cancel);
form.addEventListener('keydown',event=>{if(event.key==='Escape'&&!busy){event.preventDefault();cancel()}});
reauth.addEventListener('click',()=>authService.login('/dashboard/account/'));

download.addEventListener('click',async()=>{
  if(busy||!available)return;
  busy=true;controls();message('Preparing your export…');
  try{
    const blob=await authService.exportAccountData();
    if(!page.isConnected)return;
    const url=URL.createObjectURL(blob);const link=document.createElement('a');
    link.href=url;link.download=`aroyn-account-${new Date().toISOString().slice(0,10)}.jsonl`;
    document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);
    message('Your export is ready. Check your browser downloads.');
  }catch(error){if(page.isConnected)message(error.message||'Export failed. Please try again.',true)}
  finally{busy=false;if(page.isConnected)controls()}
});
form.addEventListener('submit',async event=>{
  event.preventDefault();if(busy||!available||confirmation.value!=='DELETE')return;
  busy=true;controls();reauth.hidden=true;message('Deleting your Aroyn account…');
  try{
    const result=await authService.deleteAccountData(confirmation.value);
    authService.clearLocalAccountData(result.pending
      ?'Your Aroyn access has been revoked. Stored-data cleanup is pending and will retry automatically. Please wait before signing in again.'
      :'Your Aroyn account has been deleted. Signing in again creates a new, empty account.');
  }catch(error){
    if(page.isConnected){message(error.message||'Deletion failed. Please try again.',true);if(error.code==='REAUTH_REQUIRED')reauth.hidden=false}
  }finally{busy=false;if(page.isConnected)controls()}
});
authService.init().then(async snap=>{
  if(!page.isConnected||snap.status!=='authenticated')return;
  page.querySelector('[data-data-user]').textContent=snap.user.displayName||snap.user.username;
  try{
    const retention=await authService.getDataRetention();
    if(!page.isConnected)return;
    if(retention?.historyDays!==30||retention?.snapshotDays!==7||retention?.profile!=='until-account-deletion')throw new Error('Retention settings changed. Please contact the maintainer for the current policy.');
    available=true;message('');
  }catch(error){if(page.isConnected)message(error.message,true)}
  if(page.isConnected)controls();
});

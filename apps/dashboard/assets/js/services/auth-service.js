import { storage } from '../core/storage.js';
import { API_BASE } from '../core/config.js';

const API_DEFAULT=API_BASE;

class AroynAuthService{
  constructor(){
    this.apiBase=String(storage.getRaw('runtime.apiBase',API_DEFAULT)||API_DEFAULT).replace(/\/+$/,'');
    this.token=storage.getRaw('auth.session','');
    this.user=null;
    this.status=this.token?'loading':'guest';
    this.listeners=new Set();
    this.initPromise=null;
    this.generation=0;
    window.addEventListener('storage',event=>{
      if(event.key!=='aroyn.auth.session'&&event.key!=='veyra.auth.session'&&event.key!==null)return;
      if(event.storageArea&&event.storageArea!==localStorage)return;
      // Storage events can queue behind a newer write. Never replay an obsolete
      // event over the session now stored by another tab.
      if(event.key&&typeof localStorage.getItem==='function'&&localStorage.getItem(event.key)!==event.newValue)return;
      const next=event.key===null?'':String(event.newValue||'');
      if(next===this.token&&(next||this.status!=='loading'))return;
      this.generation+=1;
      // Older tabs write only the legacy key. Mirror it only while the current
      // key still contains the replaced value, preserving any newer session.
      if(event.key==='veyra.auth.session'&&typeof localStorage.getItem==='function'&&localStorage.getItem('aroyn.auth.session')===event.oldValue)storage.setRaw('auth.session',next);
      this.initPromise=null;
      this.token='';this.user=null;this.status='guest';this.emit();
      // The shell reloads from shared storage; do not erase a replacement token.
      window.dispatchEvent(new CustomEvent('aroyn:auth-logout'));
    });
  }
  subscribe(fn){this.listeners.add(fn);return()=>this.listeners.delete(fn)}
  emit(){const snap=this.getSnapshot();this.listeners.forEach(fn=>{try{fn(snap)}catch(err){console.error('[Aroyn] auth listener failed',err)}})}
  getSnapshot(){return{status:this.status,token:this.token,user:this.user,apiBase:this.apiBase}}
  isAuthenticated(){return Boolean(this.token&&this.user)}
  authHeaders(extra={}){return this.token?{...extra,Authorization:`Bearer ${this.token}`}:{...extra}}
  requestTicket(){return{token:this.token,generation:this.generation}}
  requestCurrent(ticket){return ticket.token===this.token&&ticket.generation===this.generation}
  assertRequestCurrent(ticket){if(!this.requestCurrent(ticket)){const error=new Error('The Aroyn session changed.');error.code='AUTH_CHANGED';throw error}}
  async init(){
    if(this.initPromise)return this.initPromise;
    this.initPromise=this.#init();
    return this.initPromise;
  }
  async #init(){
    const ticket=this.requestTicket();
    const url=new URL(location.href);
    const exchange=url.searchParams.get('aroyn_auth')||url.searchParams.get('veyra_auth');
    if(exchange){
      url.searchParams.delete('veyra_auth');
      url.searchParams.delete('aroyn_auth');
      history.replaceState(history.state,'',url.pathname+url.search+url.hash);
      this.status='loading';this.emit();
      try{
        const response=await fetch(`${this.apiBase}/api/v2/auth/exchange`,{
          method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},
          body:JSON.stringify({code:exchange}),cache:'no-store',signal:AbortSignal.timeout(8000)
        });
        const body=await response.json().catch(()=>({}));
        if(!this.requestCurrent(ticket))return this.getSnapshot();
        if(!response.ok||!body.token||!body.user)throw new Error(body.error||`Login failed (${response.status})`);
        this.token=body.token;this.user=body.user;this.status='authenticated';storage.setRaw('auth.session',this.token);this.emit();
        window.dispatchEvent(new CustomEvent('aroyn:auth-login',{detail:{user:this.user}}));
        return this.getSnapshot();
      }catch(err){
        if(!this.requestCurrent(ticket))return this.getSnapshot();
        this.token='';this.user=null;this.status='guest';storage.setRaw('auth.session','');this.emit();
        window.dispatchEvent(new CustomEvent('aroyn:auth-error',{detail:{message:err instanceof Error?err.message:String(err)}}));
        return this.getSnapshot();
      }
    }
    if(!this.token){this.status='guest';this.emit();return this.getSnapshot()}
    try{
      const response=await fetch(`${this.apiBase}/api/v2/auth/me`,{headers:this.authHeaders({'Accept':'application/json'}),cache:'no-store',signal:AbortSignal.timeout(8000)});
      const body=await response.json().catch(()=>({}));
      if(!this.requestCurrent(ticket))return this.getSnapshot();
      if(!response.ok||!body.user)throw new Error(body.error||`Session expired (${response.status})`);
      this.user=body.user;this.status='authenticated';this.emit();
    }catch{
      if(!this.requestCurrent(ticket))return this.getSnapshot();
      this.token='';this.user=null;this.status='guest';storage.setRaw('auth.session','');this.emit();
    }
    return this.getSnapshot();
  }
  login(returnTo=location.pathname+location.search){
    const target=`${this.apiBase}/api/v2/auth/discord/start?returnTo=${encodeURIComponent(returnTo||'/dashboard/')}`;
    location.href=target;
  }
  async refreshUser(){
    if(!this.token)return null;
    const ticket=this.requestTicket();
    const response=await fetch(`${this.apiBase}/api/v2/auth/me`,{headers:this.authHeaders({'Accept':'application/json'}),cache:'no-store',signal:AbortSignal.timeout(8000)});
    const body=await response.json().catch(()=>({}));
    this.assertRequestCurrent(ticket);
    if(!response.ok||!body.user)throw new Error(body.error||`Account refresh failed (${response.status})`);
    this.user=body.user;this.status='authenticated';this.emit();return this.user;
  }
  async generateDashboardKey(confirm=false){
    if(!this.token)throw new Error('Sign in with Discord first.');
    const ticket=this.requestTicket();
    const response=await fetch(`${this.apiBase}/api/v2/dashboard-key/generate`,{
      method:'POST',headers:this.authHeaders({'Content-Type':'application/json','Accept':'application/json'}),
      body:JSON.stringify({confirm:Boolean(confirm)}),cache:'no-store',signal:AbortSignal.timeout(8000)
    });
    const body=await response.json().catch(()=>({}));
    this.assertRequestCurrent(ticket);
    if(!response.ok)throw new Error(body.error||`Key generation failed (${response.status})`);
    await this.refreshUser();
    this.assertRequestCurrent(ticket);
    return body;
  }
  async logout(){
    const token=this.token;
    this.generation+=1;
    this.token='';this.user=null;this.status='guest';storage.setRaw('auth.session','');this.emit();
    if(token){
      try{await fetch(`${this.apiBase}/api/v2/auth/logout`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Accept':'application/json'},cache:'no-store',signal:AbortSignal.timeout(8000)})}catch{}
    }
    window.dispatchEvent(new CustomEvent('aroyn:auth-logout'));
  }
  async exportAccountData(){
    const response=await fetch(`${this.apiBase}/api/v2/account/export`,{headers:this.authHeaders({'Accept':'application/x-ndjson'}),cache:'no-store'});
    if(!response.ok){const body=await response.json().catch(()=>({}));throw new Error(body.error||`Export failed (${response.status})`)}
    const contents=await response.text();
    const records=contents.trim().split('\n');
    const last=JSON.parse(records.at(-1)||'null');
    if(last?.type!=='complete'||last.data?.complete!==true)throw new Error('Export interrupted. Please try again.');
    return new Blob([contents],{type:'application/x-ndjson;charset=utf-8'});
  }
  async getDataRetention(){
    const response=await fetch(`${this.apiBase}/api/v2/account/retention`,{headers:this.authHeaders({'Accept':'application/json'}),cache:'no-store'});
    const body=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error('Account data tools are unavailable on this server. Please try again later.');
    return body.retention;
  }
  async deleteAccountData(confirmation){
    const response=await fetch(`${this.apiBase}/api/v2/account/delete`,{method:'POST',headers:this.authHeaders({'Content-Type':'application/json','Accept':'application/json'}),body:JSON.stringify({confirmation}),cache:'no-store'});
    const body=await response.json().catch(()=>({}));
    if(!response.ok||!body.ok){const error=new Error(body.error||`Deletion failed (${response.status})`);error.code=body.code;throw error}
    return body;
  }
  clearLocalAccountData(notice){
    this.generation+=1;
    for(const store of [localStorage,sessionStorage]){
      try{for(const key of Object.keys(store))if(key.startsWith('aroyn.')||key.startsWith('veyra.'))store.removeItem(key)}catch{}
    }
    if(notice){try{sessionStorage.setItem('aroyn.accountDeletionNotice',notice)}catch{}}
    this.token='';this.user=null;this.status='guest';this.emit();
    window.dispatchEvent(new CustomEvent('aroyn:auth-logout'));
  }
}

export const authService=new AroynAuthService();
export { API_DEFAULT as DEFAULT_API_BASE };


const prefix='aroyn.', legacyPrefix='veyra.';
function readRaw(key,fallback){
  try{
    const value=localStorage.getItem(prefix+key);
    if(value!==null)return value;
    const legacy=localStorage.getItem(legacyPrefix+key);
    if(legacy===null)return fallback;
    try{localStorage.setItem(prefix+key,legacy)}catch{}
    return legacy;
  }catch{return fallback;}
}
function writeRaw(key,value){
  try{localStorage.setItem(prefix+key,String(value))}catch{}
  // Keep old cached tabs from restoring an obsolete session after sign-out.
  if(key==='auth.session')try{localStorage.setItem(legacyPrefix+key,String(value))}catch{}
}
export const storage={
  get(key,fallback){try{const v=readRaw(key,null);return v===null?fallback:JSON.parse(v)}catch{return fallback}},
  set(key,value){try{writeRaw(key,JSON.stringify(value))}catch{}},
  getRaw:readRaw,setRaw:writeRaw,
  remove(key){for(const p of [prefix,legacyPrefix])try{localStorage.removeItem(p+key)}catch{}},
};

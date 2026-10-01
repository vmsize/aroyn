
const prefix='veyra.';
export const storage={get(key,fallback){try{const v=localStorage.getItem(prefix+key);return v===null?fallback:JSON.parse(v)}catch{return fallback}},set(key,value){try{localStorage.setItem(prefix+key,JSON.stringify(value))}catch{}},getRaw(key,fallback){try{return localStorage.getItem(prefix+key)??fallback}catch{return fallback}},setRaw(key,value){try{localStorage.setItem(prefix+key,String(value))}catch{}}};

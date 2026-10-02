import { initPage, subscribePage, escapeHTML } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
import { formatMoney } from '../utils/number-format.js';

initPage('inventory','Inventory');

const summaryHost=document.querySelector('[data-inventory-summary]');
const body=document.querySelector('[data-inventory-body]');
const empty=document.querySelector('[data-inventory-empty]');
const countTag=document.querySelector('[data-inventory-count]');
const search=document.querySelector('[data-inventory-search]');
const filters=document.querySelector('[data-inventory-filters]');
const wormBody=document.querySelector('[data-inventory-worms]');
const wormEmpty=document.querySelector('[data-inventory-worms-empty]');

let lastSnapshot=runtimeService.getSnapshot();
let activeFilter='all';
let query='';

function trim(s){return String(s).replace(/\.0+$/,'').replace(/(\.\d*[1-9])0+$/,'$1')}
function int(value){const n=Number(value);return Number.isFinite(n)?Math.round(n).toLocaleString():'0'}
function x(value){const n=Number(value);return Number.isFinite(n)?`${trim(n.toFixed(2))}x`:'—'}
function pct(value){const n=Number(value);return Number.isFinite(n)?`${trim((n*100).toFixed(3))}%`:'—'}
function mutList(value){
  if(Array.isArray(value))return value.filter(v=>typeof v==='string'&&v.trim());
  if(typeof value==='string')return value.split(',').map(v=>v.trim()).filter(Boolean);
  return [];
}
function chips(values){
  const arr=mutList(values);
  if(!arr.length)return '<span class="inventory-none">None</span>';
  return `<span class="inventory-mutation-list">${arr.map(v=>`<span class="inventory-mutation">${escapeHTML(v)}</span>`).join('')}</span>`;
}
function summaryMetric(label,value,note=''){
  return `<div class="stat-block"><div class="stat-label">${escapeHTML(label)}</div><div class="stat-value">${escapeHTML(value)}</div>${note?`<div class="stat-note">${escapeHTML(note)}</div>`:''}</div>`;
}
function itemSearchText(item){
  return [
    item.name,item.itemType,item.seedType,item.fruitName,item.gearId,item.petName,item.petType,
    item.rarity,item.source,...mutList(item.mutations)
  ].filter(Boolean).join(' ').toLowerCase();
}

function itemSortValue(item){
  if(item.itemType==='Fruit'){
    const total=Number(item.stackValue);
    if(Number.isFinite(total))return total;
    const unit=Number(item.sellValue),count=Number(item.count)||1;
    return Number.isFinite(unit)?unit*count:null;
  }
  if(item.itemType==='Tree'){
    const unit=Number(item.woodValue),count=Number(item.count)||1;
    return Number.isFinite(unit)?unit*count:null;
  }
  if(item.itemType==='Seed'){
    const total=Number(item.stackValue);
    if(Number.isFinite(total))return total;
    const unit=Number(item.unitPrice),count=Number(item.count)||1;
    return Number.isFinite(unit)?unit*count:null;
  }
  return null;
}
function inventorySort(a,b){
  const av=itemSortValue(a),bv=itemSortValue(b);
  const aHas=Number.isFinite(av),bHas=Number.isFinite(bv);
  if(aHas&&bHas&&av!==bv)return bv-av;
  if(aHas!==bHas)return aHas?-1:1;
  if(String(a.itemType)!==String(b.itemType))return String(a.itemType).localeCompare(String(b.itemType));
  return String(a.name||'').localeCompare(String(b.name||''));
}
function wormSort(a,b){
  const ac=Number(a.chance),bc=Number(b.chance);
  const aHas=Number.isFinite(ac),bHas=Number.isFinite(bc);
  if(aHas&&bHas&&ac!==bc)return ac-bc;
  if(aHas!==bHas)return aHas?-1:1;
  const am=Number(a.mult),bm=Number(b.mult);
  if(Number.isFinite(am)&&Number.isFinite(bm)&&am!==bm)return bm-am;
  return String(a.displayName||a.wormType||'').localeCompare(String(b.displayName||b.wormType||''));
}
function isOther(item){return !['Seed','Tree','Fruit','Gear','Pet'].includes(String(item.itemType||''))}
function matches(item){
  if(activeFilter==='other'&&!isOther(item))return false;
  if(activeFilter!=='all'&&activeFilter!=='other'&&item.itemType!==activeFilter)return false;
  if(query&&!itemSearchText(item).includes(query))return false;
  return true;
}
function itemValue(item){
  if(item.itemType==='Seed'){
    const total=Number(item.stackValue),unit=Number(item.unitPrice);
    if(Number.isFinite(total)&&Number.isFinite(unit))return `<div class="inventory-cell-main">${escapeHTML(formatMoney(total))}</div><div class="inventory-cell-sub">${escapeHTML(formatMoney(unit))} each</div>`;
  }
  if(item.itemType==='Fruit'){
    const total=Number(item.stackValue),unit=Number(item.sellValue);
    if(Number.isFinite(total))return `<div class="inventory-cell-main">${escapeHTML(formatMoney(total))}</div>${Number.isFinite(unit)&&item.count>1?`<div class="inventory-cell-sub">${escapeHTML(formatMoney(unit))} each</div>`:''}`;
  }
  if(item.itemType==='Tree'&&Number.isFinite(Number(item.woodValue))){
    return `<div class="inventory-cell-main">${escapeHTML(formatMoney(item.woodValue))}</div><div class="inventory-cell-sub">wood value</div>`;
  }
  return '<span class="inventory-none">—</span>';
}
function itemX(item){
  if((item.itemType==='Tree'||item.itemType==='Fruit')&&Number.isFinite(Number(item.multiplier)))return escapeHTML(x(item.multiplier));
  if(item.itemType==='Pet'&&Number.isFinite(Number(item.level)))return `Lv ${escapeHTML(int(item.level))}`;
  return '<span class="inventory-none">—</span>';
}
function itemDetails(item){
  const muts=mutList(item.mutations);
  const detail=[];
  if(item.itemType==='Seed'&&item.rarity)detail.push(item.rarity);
  if(item.itemType==='Tree'){
    if(item.stageIndex!=null)detail.push(`Stage ${item.stageIndex}`);
    if(item.isDead)detail.push('Dead');
  }
  if(item.itemType==='Fruit'&&item.seedType)detail.push(item.seedType);
  if(item.itemType==='Gear'&&item.gearId)detail.push(item.gearId);
  if(item.itemType==='Pet'){
    if(item.rarity)detail.push(item.rarity);
    if(item.petType)detail.push(item.petType);
    if(Number.isFinite(Number(item.hunger)))detail.push(`Hunger ${trim(Number(item.hunger).toFixed(1))}`);
    if(item.isRainbow)detail.push('Rainbow');
  }
  if(item.favorited)detail.push('Favorited');
  const detailHtml=detail.length?`<div class="inventory-detail-line">${detail.map(v=>escapeHTML(v)).join(' · ')}</div>`:'';
  return `${chips(muts)}${detailHtml}`;
}
function itemRow(item){
  const subtitle=[
    item.seedType&&item.itemType!=='Seed'?item.seedType:null,
    item.id?`ID ${String(item.id).slice(0,8)}…`:null
  ].filter(Boolean).join(' · ');
  return `<tr>
    <td><div class="inventory-item-name">${escapeHTML(item.name||item.itemType||'Item')}</div>${subtitle?`<div class="inventory-cell-sub">${escapeHTML(subtitle)}</div>`:''}</td>
    <td><span class="inventory-type">${escapeHTML(item.itemType||'Unknown')}</span></td>
    <td>${escapeHTML(int(item.count||1))}</td>
    <td><div class="inventory-cell-main">${escapeHTML(item.source||'—')}</div><div class="inventory-cell-sub">slot ${escapeHTML(String(item.slot??'—'))}</div></td>
    <td class="inventory-value">${itemValue(item)}</td>
    <td>${itemX(item)}</td>
    <td>${itemDetails(item)}</td>
  </tr>`;
}
function render(s){
  lastSnapshot=s;
  const inv=s.live?.details?.inventory;
  const items=Array.isArray(inv?.items)?inv.items:[];
  const worms=(Array.isArray(inv?.worms)?[...inv.worms]:[]).sort(wormSort);
  const sum=inv?.summary||{};

  summaryHost.innerHTML=[
    summaryMetric('Inventory units',int(sum.totalUnits||0),`${int(sum.itemStacks||0)} stacks`),
    summaryMetric('Seeds',int(sum.seedUnits||0),Number.isFinite(Number(sum.seedCatalogCost))?`${formatMoney(sum.seedCatalogCost)} catalog cost`:'' ),
    summaryMetric('Fruit value',formatMoney(sum.fruitValue||0),`${int(sum.fruitUnits||0)} fruits`),
    summaryMetric('Tree wood value',formatMoney(sum.treeWoodValue||0),`${int(sum.treeItems||0)} inventory trees`),
    summaryMetric('Pets / Gear',`${int(sum.pets||0)} / ${int(sum.gearUnits||0)}`,`${int(worms.length)} worms`),
    summaryMetric('Storage / Hotbar',`${int(sum.storageStacks||0)} / ${int(sum.hotbarUsed||0)}`,`${int(sum.worms||0)} worms`)
  ].join('');

  const visible=items.filter(matches).sort(inventorySort);
  body.innerHTML=visible.map(itemRow).join('');
  empty.hidden=visible.length>0;
  countTag.textContent=inv?`${int(visible.length)} shown · ${int(items.length)} stacks`:'Waiting for runtime';


  wormBody.innerHTML=worms.map(w=>`<tr>
    <td><div class="inventory-item-name">${escapeHTML(w.displayName||w.wormType||'Worm')}</div><div class="inventory-cell-sub">${escapeHTML(w.wormType||'')}</div></td>
    <td>${escapeHTML(x(w.mult))}</td>
    <td>${chips(w.mutations)}</td>
    <td>${escapeHTML(pct(w.chance))}</td>
    <td>${escapeHTML(String(w.slot??'—'))}</td>
  </tr>`).join('');
  wormEmpty.hidden=worms.length>0;
}

search?.addEventListener('input',()=>{
  query=search.value.trim().toLowerCase();
  render(lastSnapshot);
});
filters?.addEventListener('click',event=>{
  const button=event.target.closest?.('[data-filter]');
  if(!button)return;
  activeFilter=button.dataset.filter||'all';
  for(const el of filters.querySelectorAll('[data-filter]'))el.setAttribute('aria-pressed',String(el===button));
  render(lastSnapshot);
});

render(lastSnapshot);
subscribePage(runtimeService, render);

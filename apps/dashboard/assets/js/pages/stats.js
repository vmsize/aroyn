import { initPage, escapeHTML } from './common.js';
import { runtimeService } from '../services/runtime-service.js';
import { formatMoney } from '../utils/number-format.js';

initPage('stats','Stats');

const summaryHost=document.querySelector('[data-stats-summary]');
const seedBody=document.querySelector('[data-seed-body]');
const seedEmpty=document.querySelector('[data-seed-empty]');
const wormBody=document.querySelector('[data-worm-body]');
const wormEmpty=document.querySelector('[data-worm-empty]');
const treeHost=document.querySelector('[data-tree-list]');
const treeEmpty=document.querySelector('[data-tree-empty]');

function trim(s){return String(s).replace(/\.0+$/,'').replace(/(\.\d*[1-9])0+$/,'$1')}
function int(value){const n=Number(value);return Number.isFinite(n)?n.toLocaleString(undefined,{maximumFractionDigits:0}):'0'}
function x(value){const n=Number(value);return Number.isFinite(n)?`${trim(n.toFixed(2))}x`:'—'}
function chance(value){const n=Number(value);return Number.isFinite(n)?`${trim((n*100).toFixed(2))}%`:'—'}
function time(value){const n=Number(value);if(!Number.isFinite(n))return '—';return new Date(n).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',second:'2-digit'})}
const SEED_CATALOG=[
  {name:'Oak Seed',key:'Oak',rarity:'Common',unitPrice:0},
  {name:'Pine Seed',key:'Pine',rarity:'Common',unitPrice:25},
  {name:'Apple Seed',key:'Apple',rarity:'Rare',unitPrice:200},
  {name:'Peach Seed',key:'Peach',rarity:'Rare',unitPrice:350},
  {name:'Fig Seed',key:'Fig',rarity:'Rare',unitPrice:500},
  {name:'Orange Seed',key:'Orange',rarity:'Epic',unitPrice:1e4},
  {name:'Lemon Seed',key:'Lemon',rarity:'Epic',unitPrice:1.5e4},
  {name:'Avocado Seed',key:'Avocado',rarity:'Epic',unitPrice:2e4},
  {name:'Cherry Seed',key:'Cherry',rarity:'Legendary',unitPrice:2.5e6},
  {name:'Mango Seed',key:'Mango',rarity:'Legendary',unitPrice:5e6},
  {name:'Coconut Seed',key:'Coconut',rarity:'Legendary',unitPrice:1e7},
  {name:'Banana Seed',key:'Banana',rarity:'Mythic',unitPrice:3e9},
  {name:'Starfruit Seed',key:'Starfruit',rarity:'Mythic',unitPrice:4.5e9},
  {name:'Dragonfruit Seed',key:'Dragonfruit',rarity:'Mythic',unitPrice:7e9},
  {name:'Glowing Seed',key:'Glowing',rarity:'Celestial',unitPrice:5e11},
  {name:'Blooming Seed',key:'Blooming',rarity:'Celestial',unitPrice:7.5e11},
  {name:'Magic Seed',key:'Magic',rarity:'Secret',unitPrice:5e14},
  {name:'Pizza Seed',key:'Pizza',rarity:'Secret',unitPrice:8.5e14},
  {name:'Diamond Seed',key:'Diamond',rarity:'Divine',unitPrice:1e18},
  {name:'Void Seed',key:'Void',rarity:'Divine',unitPrice:1.75e18},
  {name:'Mushroom Seed',key:'Mushroom',rarity:'Transcendent',unitPrice:7e21},
  {name:'Money Seed',key:'Money',rarity:'Transcendent',unitPrice:1.4e22},
  {name:'Glowshroom Seed',key:'Glowshroom',rarity:'Ancient',unitPrice:3.5e27},
  {name:'Elder Seed',key:'Elder',rarity:'Ancient',unitPrice:5e27},
  {name:'Inferno Seed',key:'Inferno',rarity:'Ethereal',unitPrice:3.5e33},
  {name:'Spirit Tree Seed',key:'Spirit tree',rarity:'Ethereal',unitPrice:5e33},
  {name:'Prismatic Seed',key:'Prismatic',rarity:'Godly',unitPrice:5e42},
  {name:'Astral Seed',key:'Astral',rarity:'Godly',unitPrice:7.5e42},
];
const SEED_RARITY_ORDER=new Map([
  ['common',0],['rare',1],['epic',2],['legendary',3],['mythic',4],['celestial',5],
  ['secret',6],['divine',7],['transcendent',8],['ancient',9],['ethereal',10],['godly',11],
]);
function normalizeSeed(value){
  let raw=String(value??'').toLowerCase().replace(/seed/g,'').replace(/[^a-z0-9]/g,'');
  if(raw==='spirit')raw='spirittree';
  return raw;
}
const SEED_CATALOG_INDEX=new Map(SEED_CATALOG.map((item,index)=>[normalizeSeed(item.key||item.name),index]));
function seedSortKey(item){
  const normalized=normalizeSeed(item?.key||item?.name||'');
  const exact=SEED_CATALOG_INDEX.get(normalized);
  if(exact!==undefined)return [0,exact,''];
  const rarity=SEED_RARITY_ORDER.get(String(item?.rarity||'').trim().toLowerCase());
  return [1,rarity===undefined?999:rarity,normalized];
}
function sortSeeds(items){
  return [...items].sort((a,b)=>{
    const ka=seedSortKey(a),kb=seedSortKey(b);
    return ka[0]-kb[0]||ka[1]-kb[1]||String(ka[2]).localeCompare(String(kb[2]));
  });
}
function buildSeedItems(liveItems){
  const observed=Array.isArray(liveItems)?liveItems:[];
  const byName=new Map();
  for(const item of observed){
    const key=normalizeSeed(item?.key||item?.name||'');
    if(key)byName.set(key,item);
  }
  const used=new Set();
  const catalog=SEED_CATALOG.map(base=>{
    const key=normalizeSeed(base.key||base.name);
    const live=byName.get(key);
    if(live)used.add(live);
    const observedPrice=Number(live?.unitPrice);
    return {
      ...base,
      ...(live||{}),
      name:base.name,
      key:base.key,
      rarity:base.rarity,
      unitPrice:Number.isFinite(observedPrice)?observedPrice:base.unitPrice,
      spawned:Number(live?.spawned)||0,
      purchased:Number(live?.purchased)||0,
      petCollected:Number(live?.petCollected)||0,
      spent:Number(live?.spent)||0,
    };
  });
  const extra=observed.filter(item=>!used.has(item));
  return [...catalog,...sortSeeds(extra)];
}

const WORM_TYPE_MUTATIONS=new Map([
  ['DewyWorm','Dewy'],['ShockedWorm','Shocked'],['DustyWorm','Dusty'],['FrostedWorm','Frosted'],
  ['InfestedWorm','Infested'],['RadioactiveWorm','Radioactive'],['ChargedWorm','Charged'],['SlimyWorm','Slimy'],
  ['GoldenWorm','Golden'],['ScaledWorm','Scaled'],['CosmicWorm','Cosmic'],
]);
function wormMutations(worm){
  const values=Array.isArray(worm?.mutations)?worm.mutations.filter(v=>typeof v==='string'&&v.trim()):[];
  const seen=new Set(values);
  const fallback=WORM_TYPE_MUTATIONS.get(String(worm?.wormType||''));
  if(fallback&&!seen.has(fallback)){values.push(fallback);seen.add(fallback)}
  return values;
}
function wormName(worm){
  const raw=String(worm?.displayName||worm?.wormType||'Worm');
  const muts=wormMutations(worm);
  if(raw===String(worm?.wormType||'')&&muts.length===1)return `${muts[0]} Worm`;
  return raw;
}
function summaryMetric(label,value,note=''){return `<div class="stat-block"><div class="stat-label">${escapeHTML(label)}</div><div class="stat-value">${escapeHTML(value)}</div>${note?`<div class="stat-note">${escapeHTML(note)}</div>`:''}</div>`}

function treeFruitWorth(tree){
  const direct=Number(tree?.fruitValue);
  if(Number.isFinite(direct))return direct;
  const fruits=Array.isArray(tree?.fruits)?tree.fruits:[];
  return fruits.reduce((sum,fruit)=>{
    const value=Number(fruit?.sellValue);
    return sum+(Number.isFinite(value)?value:0);
  },0);
}
function sortTreesByFruitWorth(trees){
  return [...trees].sort((a,b)=>{
    const diff=treeFruitWorth(b)-treeFruitWorth(a);
    if(diff!==0)return diff;
    return String(a?.seedType||'').localeCompare(String(b?.seedType||''));
  });
}

function render(snapshot){
  const details=snapshot.live?.details;
  if(!details){
    summaryHost.innerHTML=summaryMetric('Runtime','Waiting','Connect Aroyn Hub to receive session stats.');
    const seedItems=buildSeedItems([]);
    seedBody.innerHTML=seedItems.map(item=>`<tr><td><div class="table-name">${escapeHTML(item.name)}</div><div class="stats-subtle">${escapeHTML(item.rarity)}</div></td><td>0</td><td>0</td><td>0</td><td class="stats-money">${escapeHTML(formatMoney(item.unitPrice))}</td><td class="stats-money">$0</td></tr>`).join('');
    wormBody.innerHTML='';treeHost.innerHTML='';
    seedEmpty.hidden=true;wormEmpty.hidden=false;treeEmpty.hidden=false;
    return;
  }

  const seeds=details.seeds||{};const compost=details.compost||{};const worms=Array.isArray(details.worms)?details.worms:[];const trees=Array.isArray(details.trees)?details.trees:[];const sortedTrees=sortTreesByFruitWorth(trees);
  summaryHost.innerHTML=[
    summaryMetric('Seeds purchased',int(seeds.totalPurchased||0)),
    summaryMetric('Seed spend',formatMoney(seeds.totalSpend||0)),
    summaryMetric('Seed spawns',int(seeds.totalSpawns||0)),
    summaryMetric('Pet seeds collected',int(seeds.totalPetCollected||0)),
    summaryMetric('Compost fed',int(compost.seedsFed||0)),
    summaryMetric('Worms obtained',int(compost.wormsObtained||0)),
    summaryMetric('Trees planted',int(trees.length)),
  ].join('');

  const seedItems=buildSeedItems(seeds.items);
  seedBody.innerHTML=seedItems.map(item=>`<tr><td><div class="table-name">${escapeHTML(item.name||item.key||'Seed')}</div><div class="stats-subtle">${escapeHTML(item.rarity||'')}</div></td><td>${int(item.spawned)}</td><td>${int(item.purchased)}</td><td>${int(item.petCollected)}</td><td class="stats-money">${escapeHTML(formatMoney(item.unitPrice))}</td><td class="stats-money">${escapeHTML(formatMoney(item.spent))}</td></tr>`).join('');
  seedEmpty.hidden=true;

  wormBody.innerHTML=[...worms].reverse().map(worm=>{const muts=wormMutations(worm);return `<tr><td>${escapeHTML(time(worm.receivedAt))}</td><td><div class="table-name">${escapeHTML(wormName(worm))}</div><div class="stats-subtle">${escapeHTML(worm.wormType||'')}</div></td><td>${escapeHTML(x(worm.mult))}</td><td>${escapeHTML(muts.length?muts.join(', '):'None')}</td><td>${escapeHTML(chance(worm.chance))}</td></tr>`}).join('');
  wormEmpty.hidden=worms.length>0;

  const openIds=new Set([...treeHost.querySelectorAll('details[open][data-tree-id]')].map(el=>el.dataset.treeId));
  treeHost.innerHTML=sortedTrees.map(tree=>{
    const fruits=Array.isArray(tree.fruits)?tree.fruits:[];
    const fruitWorth=treeFruitWorth(tree);
    const rows=fruits.map(f=>`<tr><td>${escapeHTML(String(f.spawnIndex??'—'))}</td><td><div class="table-name">${escapeHTML(f.name||'Fruit')}</div></td><td>${escapeHTML(x(f.multiplier))}</td><td>${escapeHTML((f.mutations||[]).length?(f.mutations||[]).join(', '):'None')}</td><td class="stats-money">${escapeHTML(formatMoney(f.sellValue))}</td></tr>`).join('');
    const mut=tree.mutations&&tree.mutations!==''?tree.mutations:'No mutations';
    return `<details class="tree-stat-item" data-tree-id="${escapeHTML(tree.id||'')}"><summary><span class="tree-summary-main"><strong>${escapeHTML(tree.seedType||'Tree')}</strong><span>${escapeHTML(x(tree.multiplier))} · ${escapeHTML(mut)}</span></span><span class="tree-summary-meta">fruits worth of ${escapeHTML(formatMoney(fruitWorth))} · ${int(fruits.length)} fruits</span></summary><div class="tree-fruit-wrap">${fruits.length?`<div class="table-wrap stats-inner-table"><table><thead><tr><th>#</th><th>Fruit</th><th>Multiplier</th><th>Mutations</th><th>Value</th></tr></thead><tbody>${rows}</tbody></table></div>`:'<div class="stats-inline-empty">No fruits on this tree right now.</div>'}</div></details>`;
  }).join('');
  for(const el of treeHost.querySelectorAll('details[data-tree-id]'))if(openIds.has(el.dataset.treeId))el.open=true;
  treeEmpty.hidden=trees.length>0;
}

render(runtimeService.getSnapshot());
runtimeService.subscribe(render);

import {createRequire} from 'node:module';
import {readFile,readdir,mkdir,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';


export const folder=dirname(fileURLToPath(import.meta.url));
const require=createRequire(resolve(process.env.AROYN_TEST_DEPENDENCIES || resolve(folder,'../package.json')));
const {Miniflare,Log,LogLevel,convertV4MiniflareOptions}=require('miniflare');
const {build}=require('esbuild');
const candidate=resolve(folder,'..');

export async function createRuntime({mock=false,port=0,persistPath=null,ownerDiscordId='local-owner-not-configured',apiBindings={},liveBindings={},mockDiscordIds=['900001','900003']}={}) {
  if(!mock)throw new Error('This harness supports synthetic tests only');
  const json=data=>new Response(JSON.stringify(data),{headers:{'content-type':'application/json'}});
  const mockOutbound=async request=>{
    const url=new URL(request.url);
    if(url.hostname==='discord.com'&&url.pathname==='/api/oauth2/token') {
      const body=new URLSearchParams(await request.text());
      return json({access_token:body.get('code')==='mock-b'?'local-mock-discord-b':'local-mock-discord-token',token_type:'Bearer'});
    }
    if(url.hostname==='discord.com'&&url.pathname==='/api/v10/users/@me') {
      const second=request.headers.get('authorization')==='Bearer local-mock-discord-b';
      return json({id:mockDiscordIds[second?1:0],username:second?'otheruser':'testuser',global_name:second?'Other user':'User',avatar:null});
    }
    if(url.hostname==='thumbnails.roblox.com')return json({data:[]});
    if(url.hostname==='users.roblox.com')return json({id:900002,name:'robloxuser',displayName:'robloxuser',data:[{id:900002,name:'robloxuser',displayName:'robloxuser'}]});
    return new Response('External request disabled in local test',{status:502});
  };
  const secrets={tokenSecret:'mock-token-secret',liveTokenSecret:'mock-live-secret',presenceTokenSecret:'mock-presence-secret',statsApiSecret:'mock-stats-secret'};
  const shared={modules:true,d1Databases:{DB:'aroyn-isolated-db'},r2Buckets:{PAYLOADS:'aroyn-isolated-payloads'},outboundService:mockOutbound};
  async function bundle(path){const result=await build({entryPoints:[path],bundle:true,write:false,format:'esm',platform:'browser',target:'es2022'});return result.outputFiles[0].text;}
  const [liveSource,apiSource]=await Promise.all([bundle(resolve(candidate,'workers/live/src/index.js')),bundle(resolve(candidate,'workers/api/src/worker.js'))]);
  const mf=new Miniflare(convertV4MiniflareOptions({
    host:'127.0.0.1',port,log:new Log(LogLevel.ERROR),
    // Miniflare 5's V4 converter drops the legacy per-binding persistence
    // fields. Use its shared resource path for D1, R2 and Durable Objects.
    ...(persistPath?{resourcePersistencePath:resolve(persistPath)}:{}),
    workers:[
      {...shared,name:'live',script:liveSource,compatibilityDate:'2026-09-18',
        bindings:{ALLOWED_ORIGIN:'http://127.0.0.1:4173',REQUIRE_PRESENCE_TOKEN:'true',LIVE_TOKEN_SECRET:secrets.liveTokenSecret,PRESENCE_TOKEN_SECRET:secrets.presenceTokenSecret,STATS_API_SECRET:secrets.statsApiSecret,OWNER_DISCORD_ID:ownerDiscordId,...liveBindings},
        durableObjects:{LIVE:{className:'VeyraLiveSession',useSQLite:true},STATS:{className:'VeyraStatsHub',useSQLite:true}},
        ratelimits:{PRESENCE_RATE_LIMITER:{namespace_id:'1001',simple:{limit:120,period:60}},LIVE_RATE_LIMITER:{namespace_id:'1003',simple:{limit:120,period:60}}}},
      {...shared,name:'api',script:apiSource,compatibilityDate:'2026-09-16',
        bindings:{ALLOWED_ORIGIN:'http://127.0.0.1:4173',SITE_ORIGIN:'http://127.0.0.1:4173',DISCORD_REDIRECT_URI:'http://127.0.0.1:8787/api/v2/auth/discord/callback',DISCORD_CLIENT_ID:'local-mock-client',DISCORD_CLIENT_SECRET:'local-mock-secret',TOKEN_SECRET:secrets.tokenSecret,...apiBindings},
        ratelimits:{API_RATE_LIMITER:{namespace_id:'1002',simple:{limit:120,period:60}}},
        durableObjects:{STATS_CACHE:{className:'VeyraStatsHub',scriptName:'live',useSQLite:true},SNAPSHOT_STORAGE:{className:'AroynSnapshotStore',useSQLite:true}}}
    ]
  }));
  try {
    await mf.ready;
    const db=await mf.getD1Database('DB','api');
    const migrationFolder=resolve(candidate,'workers/api/migrations');
    for(const file of (await readdir(migrationFolder)).filter(f=>f.endsWith('.sql')).sort()) {
      const sql=(await readFile(resolve(migrationFolder,file),'utf8')).replace(/^\s*--.*$/gm,'');
      const statements=sql.split(';').map(s=>s.trim()).filter(Boolean);
      await db.batch(statements.map(s=>db.prepare(s)));
    }
    return {mf,db,api:await mf.getWorker('api'),live:await mf.getWorker('live'),oauthConfigured:true};
  } catch(error) {await mf.dispose();throw error;}
}

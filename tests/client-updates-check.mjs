import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const loader=await fs.readFile(new URL('../apps/dashboard/scripts/loader.luau',import.meta.url),'utf8');
const client=(await fs.readFile(new URL('../apps/dashboard/releases/4.3.88/greedy-growers.luau',import.meta.url),'utf8')).replaceAll('\r\n','\n');
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));assert.equal(manifest.version,'4.3.88');assert.equal(manifest.gameId,10440833423);
const update=client.slice(client.indexOf('function AroynWeb.IsRemoteVersionNewer'),client.indexOf('function AroynWeb.StartUpdateWatch'));
const indicator=client.slice(client.indexOf('    ui.RefreshUpdateStatus = function()'),client.indexOf('    ui.RefreshHeader = function()',client.indexOf('    ui.RefreshUpdateStatus = function()')));
assert(client.includes('updateManifestUrl = "https://aroyn-staging.pages.dev/scripts/version.json"'));assert(!client.includes('Update checks are disabled in this staging test.'));
const prelude=String.raw`
local requests, warnings, compiled, started, manifestValue, body, failure, compileFail, startupFail, gameId, hasCompiler
local state={running=true,generation=1}
local ui, AroynWeb, activities = {}, {}, 0
local R={updateStatusLabel={}}
local COLORS={Warning='warning'}
local function trim(value) return value:match('^%s*(.-)%s*$') end
local function warn(message) warnings[#warnings+1]=message end
local function addActivity() activities+=1 end
local os={time=function() return 123456 end}
local function pass(name) print('PASS '..name) end
local loadstring, game
local function reset()
 requests={};warnings={};compiled=0;started=0;body='return true';failure=nil;compileFail=false;startupFail=false;gameId=10440833423;hasCompiler=true
 manifestValue={version='4.3.88'};state.running=true;state.generation=1;activities=0
 loadstring=function(source,name) compiled+=1;if compileFail then return nil,'compile failed' end;return function() if startupFail then error('startup failed') end;started+=1 end end
 game={GameId=gameId,IsLoaded=function() return true end,GetService=function() return {JSONDecode=function(_,raw) if raw=='bad-json' then error('invalid json') end;return manifestValue end} end,
  HttpGet=function(_,url) requests[#requests+1]=url;if failure then error(failure) end;if url:find('/scripts/version.json',1,true) then return 'manifest' end;return body end}
end
local function runLoader()
`+loader+String.raw`
end
`+update+indicator+String.raw`
reset();runLoader();assert(#requests==2 and started==1 and compiled==1);assert(requests[1]=='https://aroyn-staging.pages.dev/scripts/version.json?t=123456');assert(requests[2]=='https://aroyn-staging.pages.dev/releases/4.3.88/greedy-growers.luau');pass('stable loader reads current manifest and runs the selected immutable release')
reset();manifestValue.version='4.3.99';runLoader();assert(requests[2]:find('/4.3.99/',1,true) and started==1);pass('same loader follows a later release without changing the saved command')
for _,version in ipairs({'../x','https://evil.test/script','4.3.88/../../x','4.3.88?token=x','','4.3.88-beta'}) do reset();manifestValue.version=version;runLoader();assert(#requests==1 and compiled==0 and #warnings==1) end
pass('invalid manifest versions cannot change host or inject a path')
reset();game.GameId=1;runLoader();assert(#requests==0 and compiled==0);reset();loadstring=nil;runLoader();assert(#requests==0);pass('unsupported game or missing compiler makes no update download')
reset();failure='network failure';runLoader();assert(compiled==0 and started==0 and #warnings==1);reset();manifestValue=nil;runLoader();assert(compiled==0 and #warnings==1)
reset();game.GetService=function() return {JSONDecode=function() error('invalid JSON') end} end;runLoader();assert(compiled==0 and #warnings==1)
reset();game.HttpGet=function() return string.rep('x',4097) end;runLoader();assert(compiled==0 and #warnings==1)
pass('manifest failure does not silently run an old release')
reset();body='<!DOCTYPE html><html>';runLoader();assert(compiled==0 and #warnings==1);reset();body=string.rep('x',900001);runLoader();assert(compiled==0 and #warnings==1);pass('HTML fallback and oversized source are rejected')
reset();compileFail=true;runLoader();assert(started==0 and #warnings==1);reset();startupFail=true;runLoader();assert(started==0 and #warnings==1)
reset();local get=game.HttpGet;game.HttpGet=function(self,url) if url:find('/releases/',1,true) then error('download failed') end;return get(self,url) end;runLoader();assert(compiled==0 and started==0 and #warnings==1)
pass('compile and startup errors stay visible without another execution')

local response, requestCount, received
local function setupUpdate()
 reset();requestCount=0;received=nil;response={StatusCode=200,Body='ok'};manifestValue={version='4.3.89',message='Update ready'}
 AroynWeb={clientVersion='4.3.88',updateManifestUrl='https://aroyn-staging.pages.dev/scripts/version.json',
  ResolveRequest=function() return function(options) requestCount+=1;received=options;return response end end,
  ParseResponseBody=function() return manifestValue end,
  IsRemoteVersionNewer=IsRemoteVersionNewer}
 -- Functions above are attached to a table, preserve their real implementations.
end
local methods=table.clone(AroynWeb)
local function setup()
 setupUpdate();for k,v in pairs(methods) do AroynWeb[k]=v end
end
setup();assert(AroynWeb.CheckUpdateOnce());assert(AroynWeb.updateAvailable and R.updateStatusLabel.Visible and R.updateStatusLabel.Text=='Update available · v4.3.89');assert(activities==1)
assert(received.Url=='https://aroyn-staging.pages.dev/scripts/version.json?t=123456' and received.Method=='GET' and received.Headers.Authorization==nil)
assert(AroynWeb.CheckUpdateOnce());assert(activities==1);assert(started==0 and compiled==0);pass('update check shows GUI notification once without credentials or executing code')
setup();manifestValue.version='4.3.88';assert(AroynWeb.CheckUpdateOnce());assert(not AroynWeb.updateAvailable and not R.updateStatusLabel.Visible);assert(AroynWeb.IsRemoteVersionNewer('4.3.100','4.3.99'));assert(not AroynWeb.IsRemoteVersionNewer('4.3.9','4.3.88'));pass('current and older releases hide the notice; version ordering is numeric')
setup();response.StatusCode=503;assert(not AroynWeb.CheckUpdateOnce());assert(AroynWeb.updateLastError=='HTTP 503');response.StatusCode=200;assert(AroynWeb.CheckUpdateOnce());assert(R.updateStatusLabel.Visible);pass('manifest error remains retryable and subsequent check restores the notice')
setup();AroynWeb.ResolveRequest=function() return function() state.running=false;state.generation+=1;return response end end;assert(not AroynWeb.CheckUpdateOnce());assert(AroynWeb.latestVersion==nil and activities==0);pass('late update response after client shutdown does not update the GUI')
setup();state.running=false;assert(not AroynWeb.CheckUpdateOnce());assert(requestCount==0);pass('stopped client does not send update checks')
`;
const runtime=await luauTestRuntime();const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-updates-'));const file=path.join(temp,'check.luau');await fs.writeFile(file,prelude);
const compile=spawnSync(runtime.compiler,['--null',file],{encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
const run=spawnSync(runtime.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);const lines=run.stdout.split(/\r?\n/).filter(l=>l.startsWith('PASS '));assert.equal(lines.length,12);console.log(run.stdout.trim());
await fs.writeFile(new URL('client-updates-results.json',import.meta.url),JSON.stringify({date:'2026-10-02',passed:12,checks:lines.map(x=>x.slice(5)),scope:'Actual stable loader, update-check and GUI indicator functions with stubbed HTTP/game objects on Luau CLI; no real game execution.'},null,2)+'\n');

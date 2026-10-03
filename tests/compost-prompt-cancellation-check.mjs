import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const src=(await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
const cut=(a,b)=>{const i=src.indexOf(a),j=src.indexOf(b,i);assert(i>=0&&j>i);return src.slice(i,j)};
const actual=cut('function FarmRuntime.featureOperationToken(', 'function FarmRuntime.acquireFeatureOperation(')+cut('function FarmRuntime.triggerCompostPrompt(', 'function FarmRuntime.compostPositionMatches(');
const pre=String.raw`
local state,CompostRuntime,PetSeedRuntime,FarmRuntime={},{},{},{AutomationRuntime={}}
local Enum={KeyCode={E=1}}
local function warn() end
local calls,holdBegins,holdEnds,keyBegins,keyEnds,mode
local fireproximityprompt,keypress,keyrelease
local task={wait=function(t)
    coroutine.yield(t)
    if mode=='wait-error' then error('synthetic wait error') end
end}
local function reset(selected)
    mode=selected;state={running=true,generation=1,autoCompostEnabled=true};CompostRuntime={workerRevision=1}
    calls,holdBegins,holdEnds,keyBegins,keyEnds=0,0,0,0,0
    fireproximityprompt=function()
        calls+=1
        if (mode=='first-error' or mode=='first-success') and calls==1 then coroutine.yield(.25)
        elseif mode=='second-error' and calls==2 then coroutine.yield(.25) end
        if mode=='first-success' then return end
        error('synthetic executor failure')
    end
    keypress=function()
        keyBegins+=1
        if mode=='key-error' then coroutine.yield(.25);error('synthetic key error') end
    end
    keyrelease=function() keyEnds+=1 end
    local prompt={Parent=true,KeyboardKeyCode=Enum.KeyCode.E,
        InputHoldBegin=function()
            holdBegins+=1
            if mode=='hold-error' or mode=='key-error' then coroutine.yield(.25);error('synthetic hold error') end
        end,
        InputHoldEnd=function() holdEnds+=1 end}
    if mode=='hold-only' or mode=='wait-error' then fireproximityprompt=nil end
    return prompt
end
local function cancel(scenario)
    if scenario=='disable' then state.autoCompostEnabled=false;CompostRuntime.workerRevision+=1
    elseif scenario=='off-on' then CompostRuntime.workerRevision+=2
    elseif scenario=='stop' then state.running=false;state.generation+=1 end
end
local function resume(co)
    local ok,value=coroutine.resume(co);assert(ok,tostring(value));return value
end
local function drain(co)
    local steps=0;while coroutine.status(co)~='dead' do steps+=1;assert(steps<20);resume(co) end
end
local function pass(name) print('PASS '..name) end
`;
const test=String.raw`
for _,stage in ipairs({'first-error','second-error','first-success'}) do
    for _,scenario in ipairs({'disable','off-on','stop'}) do
        local prompt=reset(stage);local token=FarmRuntime.featureOperationToken('compost');local result,reason
        local co=coroutine.create(function() result,reason=FarmRuntime.triggerCompostPrompt(prompt,1,token) end)
        assert(resume(co)==.25);local accepted=calls;cancel(scenario);drain(co)
        assert(calls==accepted and holdBegins==0 and keyBegins==0)
        assert(result==false and reason=='cancelled');pass(stage..' '..scenario..' starts no new interaction')
    end
end
for _,stage in ipairs({'hold-only','hold-error','wait-error'}) do
    for _,scenario in ipairs({'disable','off-on','stop'}) do
        local prompt=reset(stage);local token=FarmRuntime.featureOperationToken('compost');local result,reason
        local co=coroutine.create(function() result,reason=FarmRuntime.triggerCompostPrompt(prompt,1,token) end)
        resume(co);assert(holdBegins==1);cancel(scenario);drain(co)
        assert(holdEnds==1 and keyBegins==0 and keyEnds==0)
        assert(result==false and reason=='cancelled');pass(stage..' '..scenario..' releases hold without another attempt')
    end
end
for _,scenario in ipairs({'disable','off-on','stop'}) do
    local prompt=reset('key-error');local token=FarmRuntime.featureOperationToken('compost');local result,reason
    local co=coroutine.create(function() result,reason=FarmRuntime.triggerCompostPrompt(prompt,1,token) end)
    resume(co);resume(co);assert(holdBegins==1 and holdEnds==1 and keyBegins==1)
    cancel(scenario);drain(co);assert(keyEnds==1)
    assert(result==false and reason=='cancelled');pass('key-error '..scenario..' releases accepted keypress')
end
for _,stage in ipairs({'first-success','second-error','hold-only','hold-error'}) do
    local prompt=reset(stage);local token=FarmRuntime.featureOperationToken('compost');local result
    local co=coroutine.create(function() result=FarmRuntime.triggerCompostPrompt(prompt,1,token) end);drain(co)
    assert(result==true)
    if stage=='first-success' then assert(calls==1 and holdBegins==0)
    elseif stage=='hold-error' then assert(holdBegins==1 and holdEnds==1 and keyBegins==1 and keyEnds==1)
    else assert(holdBegins==1 and holdEnds==1 and keyBegins==0) end
    pass(stage..' ordinary interaction succeeds')
end
local prompt=reset('second-error');local token=FarmRuntime.featureOperationToken('compost');cancel('disable')
assert(FarmRuntime.triggerCompostPrompt(prompt,1,token)==false);assert(calls==0 and holdBegins==0 and keyBegins==0);pass('already cancelled token sends nothing')
`;
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-compost-prompt-'));const file=path.join(temp,'check.luau');await fs.writeFile(file,pre+actual+test);
const rt=await luauTestRuntime();const compiled=spawnSync(rt.compiler,['--null',file],{encoding:'utf8'});assert.equal(compiled.status,0,compiled.stderr);
const run=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);const checks=run.stdout.split(/\r?\n/).filter(s=>s.startsWith('PASS ')).map(s=>s.slice(5));assert.equal(checks.length,26);
const report={passed:checks.length,checks,client:manifest.version,luauVersion:rt.version,scope:'Actual triggerCompostPrompt and token predicates; synthetic yielding/error prompt/hold/key operations. No executor or game execution.'};console.log(run.stdout.trim());await fs.writeFile(new URL('compost-prompt-cancellation-results.json',import.meta.url),JSON.stringify(report,null,2)+'\n');

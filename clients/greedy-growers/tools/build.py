"""Reproduce the immutable published 4.3.96; outputs only to a new local directory."""
from pathlib import Path
import json,hashlib,argparse,sys
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1];sys.path.insert(0,str(REPO/'tools'))
from luau_cli import compile_file
def build(output):
    meta=json.loads((ROOT/'release.json').read_text(encoding='utf-8'));source=ROOT/'src';out=Path(output).resolve()
    if out==ROOT or out in ROOT.parents or source==out or source in out.parents:raise ValueError('Choose an isolated output outside source')
    if out.exists() and any(out.iterdir()):raise ValueError('Output must be empty')
    for name,identity in meta['sources'].items():
        raw=(source/name).read_bytes();assert hashlib.sha256(raw).hexdigest()==identity['sha256'] and len(raw)==identity['size'],name
    read=lambda name:(source/name).read_text(encoding='utf-8')
    bundle=meta['banner']+'local HubStorage=(function()\n'+read('Storage.luau')+'\nend)()\n'
    bundle+='local function HubDashboardFactory(C)\nlocal factory=(function()\n'+read('Dashboard.luau')+'\nend)()\nreturn factory(C)\nend\n'
    for name,file in [('LoadAroyn','Aroyn.luau'),('AssetFactory','Assets.luau'),('UIFactory','GameUI.luau'),('StartupFactory','Startup.luau')]:bundle+='local function '+name+'()\n'+read(file)+'\nend\n'
    bundle+='local function Runtime(Aroyn,BuildUI,Options)\n'+read('GreedyRuntime.luau')+'\nend\n'
    metadata='return {'+','.join(k+'='+json.dumps(v,ensure_ascii=False) for k,v in meta['metadata'].items())+'}\n'
    assert metadata==read('BuildInfo.luau')
    bundle+='local function MetadataFactory()\n'+metadata+'end\n'
    bundle+='return StartupFactory().Run(LoadAroyn(),MetadataFactory(),AssetFactory(),Runtime,UIFactory(),{DashboardAutoConnect=false,Storage=HubStorage})\n'
    data=bundle.encode('utf-8');assert len(data)==meta['expectedBytes'] and hashlib.sha256(data).hexdigest()==meta['expectedSHA256'],'Reproduction mismatch; never replace published bytes'
    assert data==(ROOT/meta['artifact']).read_bytes()
    out.mkdir(parents=True,exist_ok=True);p=out/'AroynHub-4.3.96.luau';p.write_bytes(data);compile_file(p)
    (out/'SHA256SUMS').write_text(meta['expectedSHA256']+'  '+p.name+'\n',encoding='ascii')
    print('PASS Hub exact reproduction: '+str(len(data))+' bytes / '+meta['expectedSHA256']);return p
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args();build(args.output)

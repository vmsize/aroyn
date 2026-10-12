"""Authentic modules -> exactly the already-published v0.1.0. No promotion/network."""
from pathlib import Path
import base64,json,hashlib,argparse,sys
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1];sys.path.insert(0,str(REPO/'tools'))
from luau_cli import compile_file
def build(output):
    out=Path(output).resolve();release=json.loads((ROOT/'release.json').read_text());read=lambda name:(ROOT/name).read_text(encoding='utf-8').replace('\r\n','\n')
    if out==ROOT or out in ROOT.parents or ROOT/'src'==out or ROOT/'src' in out.parents:raise ValueError('Output must be isolated from source')
    if out.exists() and any(out.iterdir()):raise ValueError('Output must be empty')
    for name,identity in release['sources'].items():
        raw=(ROOT/name).read_bytes();assert len(raw)==identity['size'] and hashlib.sha256(raw).hexdigest()==identity['sha256'],name
    assert hashlib.sha256((ROOT/'src/Aroyn.luau').read_bytes()).hexdigest()==release['coreSHA256']
    payload=[]
    for image in release['assets']:
        data=(ROOT/image['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==image['sha256'];payload.append('{Field=%s,SHA256=%s,Base64=%s}'%(json.dumps(image['field']),json.dumps(image['sha256']),json.dumps(base64.b64encode(data).decode())))
    entry=read('src/Entry.luau')
    for token,value in {'@@CORE@@':read('src/Aroyn.luau'),'@@ADAPTER@@':read('src/Assets.luau'),'@@PAYLOAD@@':',\n'.join(payload),'@@VERSION@@':json.dumps(release['version']),'@@CORE_HASH@@':json.dumps(release['coreSHA256'])}.items():assert entry.count(token)==1;entry=entry.replace(token,value)
    entry=entry.replace('Channel="development"','Channel="stable"').replace('-- Aroyn UI standalone local development artifact. No public release or endpoint.','-- Aroyn UI standalone approved stable artifact.')
    entry='--[[\n'+read('LICENSE')+'\n'+read('BRAND_NOTICE.md')+'\n]]\n'+entry;data=entry.encode('utf-8')
    assert len(data)==release['expectedBytes'] and hashlib.sha256(data).hexdigest()==release['expectedSHA256'],'Existing stable reproduction mismatch'
    assert data==(ROOT/'releases/0.1.0/Aroyn.lua').read_bytes()
    out.mkdir(parents=True,exist_ok=True);p=out/'Aroyn.lua';p.write_bytes(data);compile_file(p)
    demo='-- Local standalone showcase; no remote downloads. This example intentionally creates a window.\nlocal Aroyn=(function()\n'+entry+'\nend)()\nlocal createExample=(function()\n'+read('examples/showcase.factory.luau')+'\nend)()\nreturn createExample(Aroyn,game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"))\n';d=out/'ShowcaseDemo.luau';d.write_text(demo,encoding='utf-8',newline='\n');compile_file(d)
    (out/'SHA256SUMS').write_text(release['expectedSHA256']+'  Aroyn.lua\n',encoding='ascii');print('PASS UI exact reproduction: '+str(len(data))+' bytes / '+release['expectedSHA256']);return p
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args();build(args.output)

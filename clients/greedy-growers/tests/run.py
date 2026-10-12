"""Authentic 4.3.96 controller/startup/config/mobile cases; no Roblox or production I/O."""
from pathlib import Path
import json,sys,tempfile,subprocess,shutil,hashlib
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1];sys.path.insert(0,str(REPO/'tools'))
from luau_cli import cli
read=lambda name:(ROOT/name).read_text(encoding='utf-8')
src=lambda name:read('src/'+name)
bundle=(ROOT/'../../apps/dashboard/releases/4.3.96/greedy-growers.luau').read_text(encoding='utf-8')
storage="local function StorageFactory()\n"+src('Storage.luau')+"\nend\nlocal sf,FE=Mock.install(StorageFactory,true)\nFE.isfile=function(p)return Mock.files[p]~=nil end\nFE.writefile=function(p,v)if Mock.writeFault then return Mock.writeFault(p,v) end;Mock.files[p]=v end\nlocal HubStorage=sf()\n"
dash="Options.DashboardFactory=function(C) local f=(function()\n"+src('Dashboard.luau')+"\nend)();return f(C) end\n"
pre="local Mock=require('./mock')\n"+storage
for name,file in [('CoreFactory','Aroyn.luau'),('UIFactory','GameUI.luau'),('AssetsFactory','Assets.luau'),('BuildInfoFactory','BuildInfo.luau'),('MetadataFactory','BuildInfo.luau'),('StartupFactory','Startup.luau')]:pre+='local function '+name+'()\n'+src(file)+'\nend\n'
pre+='local function RuntimeFactory(Aroyn,BuildUI,Options)\nOptions.BuildInfo=Options.BuildInfo or BuildInfoFactory();Options.Storage=HubStorage\n'+dash+src('GreedyRuntime.luau')+'\nend\n'
for name in ['BundleFactory','ProductionBundleFactory']:pre+='local function '+name+'()\n'+bundle+'\nend\n'
# Historical native-verification fixture uses the same authentic runtime and
# isolated metadata, never a second published executable or gameplay rewrite.
release=json.loads(read('release.json'));native=json.loads(read('tests/fixtures/native-build-info.json'))
old='return {'+','.join(k+'='+json.dumps(v,ensure_ascii=False) for k,v in release['metadata'].items())+'}\n'
new='return {'+','.join(k+'='+json.dumps(v,ensure_ascii=False) for k,v in native.items())+'}\n'
assert bundle.count(old)==1
native_bundle=bundle.replace(old,new).replace('-- Aroyn Hub 4.3.96 production candidate; NOT published.','-- Aroyn Hub 4.3.96 native candidate; NOT published.',1)
identity=json.loads(read('tests/fixtures/native-identity.json'))
assert len(native_bundle.encode())==identity['bytes'] and hashlib.sha256(native_bundle.encode()).hexdigest()==identity['sha256']
pre+='local function NativeBundleFactory()\n'+native_bundle+'\nend\n'
def run(name,body):
    with tempfile.TemporaryDirectory(prefix='aroyn-hub-'+name+'-') as folder:
        out=Path(folder);shutil.copyfile(ROOT/'tests/support/mock.luau',out/'mock.luau');shutil.copyfile(ROOT/'tests/support/config-json-mock.luau',out/'config-json-mock.luau')
        p=out/'run.luau';p.write_text(pre+body,encoding='utf-8',newline='\n');q=subprocess.run([cli()['runtime'],str(p)],capture_output=True,text=True,encoding='utf-8',timeout=120);print('SUITE '+name);print(q.stdout);assert q.returncode==0,q.stderr
run('integration',read('tests/cases/integration.luau'))
startup=read('tests/cases/startup.luau');run('startup',startup)
release=read('tests/cases/tests_release.luau');run('release',release+'\n'+read('tests/cases/tests_final.luau'))
run('autosave-dashboard',release[:release.index('local expected=')]+'\n'+read('tests/cases/tests_autosave_dashboard.luau'))
fixtures=startup[:startup.index('Mock.asyncTweens=true')]+'\nMock.asyncTweens=true\n'
for name,extra in [('assets-hotfix','tests_assets_hotfix'),('mobile-renderer','tests_mobile_renderer'),('sidebar','tests_sidebar')]:run(name,fixtures+'\nlocal s\n'+read('tests/cases/'+extra+'.luau'))
audit=read('tests/cases/tests_mobile_audit.luau');audit=audit[:audit.index("print('MOBILE_AUDIT_JSON '")];run('responsive',audit+'\n'+read('tests/cases/tests_responsive.luau')+"\nfor _,case in ipairs(cases) do assert(case.Status=='PASS',case.Id..': '..tostring(case.Detail));print('PASS '..case.Id) end\n")
print('PASS Hub actual-source regression suites; native/physical platform testing SKIP')

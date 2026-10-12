"""Current core and exact stable bundle exercised with deterministic Roblox doubles."""
from pathlib import Path
import sys,tempfile,shutil,subprocess,json
sys.stdout.reconfigure(encoding='utf-8')
ROOT=Path(__file__).resolve().parent.parent;REPO=ROOT.parents[1];sys.path.insert(0,str(REPO/'tools'))
from luau_cli import cli
read=lambda name:(ROOT/name).read_text(encoding='utf-8')
def run(driver,name):
    with tempfile.TemporaryDirectory(prefix='aroyn-ui-'+name+'-') as folder:
        out=Path(folder);shutil.copyfile(ROOT/'tests/support/mock.luau',out/'mock.luau');shutil.copyfile(ROOT/'tests/support/config-json-mock.luau',out/'config-json-mock.luau')
        p=out/'run.luau';p.write_text(driver.replace("require('../config-json-mock')","require('./config-json-mock')"),encoding='utf-8',newline='\n')
        q=subprocess.run([cli()['runtime'],str(p)],capture_output=True,text=True,encoding='utf-8',timeout=90);print(q.stdout);assert q.returncode==0,q.stderr
        return len([s for s in q.stdout.splitlines() if s.startswith('PASS ')])
pre="local Mock=require('./mock')\nlocal results={}\nlocal function pass(message) table.insert(results,message);print('PASS '..message) end\n"
for mode,library in [('source',read('src/Aroyn.luau')),('stable',read('releases/0.1.0/Aroyn.lua'))]:
    driver=pre+'local function LibraryFactory()\n'+library+'\nend\nlocal makeLibrary,libraryEnvironment=Mock.install(LibraryFactory)\nlocal function ExampleFactory()\n'+read('examples/basic.factory.luau')+'\nend\nlocal makeExample=Mock.install(ExampleFactory)\n'
    names=['library-tests','library-motion-tests','advanced-tests','dropdown-toggle-tests','dropdown-direction-tests','keybind-tests','colorpicker-tests','overlay-tests','overlay-polish-tests','config-tests','audit-tests']
    driver+='\n'.join(read('tests/cases/'+n+'.luau') for n in names)+'\nprint("TOTAL "..#results)\n';print('MODE '+mode);run(driver,mode)
driver='local Mock=require("./mock")\nlocal function SourceFactory()\n'+read('src/Aroyn.luau')+'\nend\nlocal function BundleFactory()\n'+read('releases/0.1.0/Aroyn.lua')+'\nend\nlocal function ShowcaseFactory()\n'+read('examples/showcase.factory.luau')+'\nend\n'+read('tests/cases/distribution.luau')
print('MODE stable-distribution');run(driver,'distribution')
for mode,library in [('source',read('src/Aroyn.luau')),('stable',read('releases/0.1.0/Aroyn.lua'))]:
    driver='local Mock=require("./mock")\nlocal function LibraryFactory()\n'+library+'\nend\nlocal makeLibrary=Mock.install(LibraryFactory)\nlocal function ConfigurationFactory()\n'+read('examples/configuration.factory.luau')+'\nend\nlocal makeExample=Mock.install(ConfigurationFactory)\nlocal example=makeExample()(makeLibrary(),Mock.Instance.new("PlayerGui"))\nassert(example~=nil)\nexample:Destroy()\nprint("PASS configuration example construction and cleanup")\n'
    print('MODE configuration-example-'+mode);run(driver,'configuration-example-'+mode)
print('PASS UI source/stable/distribution existing regression cases; native rendering and physical device testing SKIP')

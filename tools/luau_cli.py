"""Portable callers share the existing checksum-pinned official Node downloader."""
from pathlib import Path
import json,subprocess,os,shutil
ROOT=Path(__file__).resolve().parent.parent
def cli():
    override=os.environ.get('LUAU_BIN_DIR')
    if override:
        root=Path(override);ext='.exe' if os.name=='nt' else ''
        runtime=root/('luau'+ext);compiler=root/('luau-compile'+ext)
        if not runtime.is_file() or not compiler.is_file():raise ValueError('LUAU_BIN_DIR must contain luau and luau-compile')
        return {'runtime':str(runtime),'compiler':str(compiler),'version':'explicit developer override (not pinned)'}
    script="import {luauTestRuntime} from './tools/luau-test-runtime.mjs'; console.log(JSON.stringify(await luauTestRuntime()));"
    result=subprocess.run(['node','--input-type=module','-e',script],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
    if result.returncode:raise RuntimeError(result.stderr)
    return json.loads(result.stdout.strip().splitlines()[-1])
def compile_file(file):
    result=subprocess.run([cli()['compiler'],'--null',str(file)],capture_output=True,text=True,encoding='utf-8')
    if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    return result.stdout

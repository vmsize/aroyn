import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

// Official development CLI only; no Roblox/executor connection or game calls.
const version='0.740';
const platforms={win32:['windows','be676d9a1092b3d5ee36be5f5f11e2af1976911c32f5644a052548dc7c66bb9c'],linux:['ubuntu','7d4035db01816f977f6e4c42e3d5e8ef4235d95e9afe63a3c38905b42dde60f2'],darwin:['macos','8414763743116cbc2533ee7c932d41ba66bd25ea7c2353bc7eed2934b60b6715']};
export async function luauTestRuntime(){
 const spec=platforms[process.platform];if(!spec)throw new Error('Unsupported Luau test platform');
 const dir=path.join(os.tmpdir(),'aroyn-luau-tests',version,process.platform);await fs.mkdir(dir,{recursive:true});
 const ext=process.platform==='win32'?'.exe':'';
 const runtime=path.join(dir,'luau'+ext),compiler=path.join(dir,'luau-compile'+ext);
 try{await fs.access(runtime);await fs.access(compiler);return {runtime,compiler,version};}catch{}
 const url=`https://github.com/luau-lang/luau/releases/download/${version}/luau-${spec[0]}.zip`;
 const response=await fetch(url,{signal:AbortSignal.timeout(60000)});if(!response.ok)throw new Error('Luau CLI download '+response.status);
 const bytes=Buffer.from(await response.arrayBuffer());if(crypto.createHash('sha256').update(bytes).digest('hex')!==spec[1])throw new Error('Luau CLI archive hash mismatch');
 const zip=path.join(dir,'luau.zip');await fs.writeFile(zip,bytes);
 const psQuote=value=>"'"+value.replaceAll("'","''")+"'";
 const unpack=await fs.mkdtemp(path.join(dir,'unpack-'));
 const result=process.platform==='win32'?spawnSync('powershell',['-NoProfile','-NonInteractive','-Command',`$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory(${psQuote(zip)}, ${psQuote(unpack)})`],{encoding:'utf8'}):spawnSync('unzip',['-o',zip,'-d',unpack],{encoding:'utf8'});
 if(result.status!==0)throw new Error('Luau extraction failed: '+result.stderr);
 await fs.copyFile(path.join(unpack,'luau'+ext),runtime);await fs.copyFile(path.join(unpack,'luau-compile'+ext),compiler);
 if(process.platform!=='win32'){await fs.chmod(runtime,0o755);await fs.chmod(compiler,0o755);}
 await fs.access(runtime);await fs.access(compiler);return {runtime,compiler,version};
}

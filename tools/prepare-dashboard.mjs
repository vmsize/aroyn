import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

function publicHTTPS(value, name) {
  let url;
  try { url = new URL(value); } catch { throw new Error(`${name} requires a public HTTPS URL`); }
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      !host.includes('.') || host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local') ||
      /^[\d.]+$/.test(host) || host.includes(':') || host.startsWith('[')) throw new Error(`${name} requires a public HTTPS hostname without credentials, query or fragment`);
  return url;
}

export function deploymentConfig({ apiBase, liveBase, scriptLoaderUrl = '' }) {
  const api = publicHTTPS(apiBase, 'API base');
  const live = publicHTTPS(liveBase, 'Live base');
  if (api.pathname !== '/' || live.pathname !== '/') throw new Error('Worker endpoints must be origins without a path');
  if (scriptLoaderUrl) {
    const loader = publicHTTPS(scriptLoaderUrl, 'Loader URL');
    if (!loader.pathname.endsWith('.luau')) throw new Error('Loader URL must point to a .luau file');
  }
  const socket = new URL('/ws', live); socket.protocol = 'wss:';
  return '// Generated deployment configuration. Local preview defaults are not uploaded.\n' +
    Object.entries({ API_BASE: api.origin, LIVE_BASE: live.origin, LIVE_WS_BASE: socket.href, SCRIPT_LOADER_URL: scriptLoaderUrl })
      .map(([key, value]) => `export const ${key} = ${JSON.stringify(value)};`).join('\n') + '\n';
}

export async function prepareDashboard({ source, output, apiBase, liveBase, scriptLoaderUrl = '', restrictedStaging = false }) {
  const config = deploymentConfig({ apiBase, liveBase, scriptLoaderUrl });
  const input = await fs.realpath(source);
  const target = path.resolve(output);
  const relative = path.relative(input, target);
  if (!relative || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) throw new Error('Output must be outside the source directory');
  // An empty output avoids stale assets and never deletes an existing directory.
  try { if ((await fs.readdir(target)).length) throw new Error('Output directory must be empty'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  await fs.mkdir(target, { recursive: true });
  let files = 0;
  async function copy(dir, rel = '') {
    for (const item of await fs.readdir(dir, { withFileTypes: true })) {
      if (['node_modules', '.git', '.private', '.wrangler', 'package.json', 'package-lock.json', 'dev-server.mjs'].includes(item.name) || item.name.startsWith('.')) continue;
      const next = path.join(rel, item.name);
      if (item.isDirectory()) { await copy(path.join(dir, item.name), next); continue; }
      if (!item.isFile()) throw new Error(`Unsupported source entry: ${next}`);
      const destination = path.join(target, next); await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.copyFile(path.join(dir, item.name), destination); files++;
    }
  }
  await copy(input);
  const configPath = path.join(target, 'assets/js/core/config.js');
  await fs.access(configPath); await fs.writeFile(configPath, config);
  const headers = (restrictedStaging ? '/*\n  X-Robots-Tag: noindex, nofollow\n' : '/*\n') +
    '  X-Content-Type-Options: nosniff\n  Referrer-Policy: no-referrer\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n\n' +
    '/assets/js/*\n  Cache-Control: no-store\n\n/scripts/*\n  Cache-Control: no-store\n  Content-Type: text/plain; charset=utf-8\n\n' +
    '/releases/*\n  Cache-Control: public, max-age=31536000, immutable\n  Content-Type: text/plain; charset=utf-8\n';
  await fs.writeFile(path.join(target, '_headers'), headers);
  return { files, output: target, apiBase: new URL(apiBase).origin, liveBase: new URL(liveBase).origin };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2); const values = {};
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (key === '--restricted-staging') { values.restrictedStaging = true; continue; }
    const name = { '--source': 'source', '--output': 'output', '--api-base': 'apiBase', '--live-base': 'liveBase', '--loader-url': 'scriptLoaderUrl' }[key];
    if (!name || !args[i + 1] || args[i + 1].startsWith('--')) throw new Error(`Invalid argument: ${key}`);
    values[name] = args[++i];
  }
  values.source ||= fileURLToPath(new URL('../apps/dashboard/', import.meta.url));
  if (!values.output) throw new Error('--output is required');
  console.log(JSON.stringify(await prepareDashboard(values)));
}

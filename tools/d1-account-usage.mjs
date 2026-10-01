import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const GROUP_LIMIT = 1000;
const accountPattern = /^[a-f0-9]{32}$/;
const databasePattern = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;
function utcDay(time) {
  if (!Number.isSafeInteger(time) || time <= 0) throw new Error('Valid capture clock required');
  return new Date(time).toISOString().slice(0, 10);
}

// One account, one UTC day, all database groups, including deleted databases.
// Never derive a spending allowance from the current database inventory.
export function d1UsageQuery(accountId, time) {
  if (!accountPattern.test(accountId)) throw new Error('Valid Cloudflare account ID required');
  const date = utcDay(time);
  return `query { viewer { accounts(filter: {accountTag: "${accountId}"}) { accountTag d1AnalyticsAdaptiveGroups(limit: ${GROUP_LIMIT}, filter: {date_geq: "${date}", date_leq: "${date}"}) { sum { rowsRead rowsWritten } dimensions { date databaseId } } } } }`;
}

export function normalizeD1Usage(body, {accountId, startedAt, collectedAt}) {
  if (!accountPattern.test(accountId)) throw new Error('Valid Cloudflare account ID required');
  const date = utcDay(startedAt);
  if (utcDay(collectedAt) !== date || collectedAt < startedAt || collectedAt - startedAt > 300000) throw new Error('Capture crossed UTC day or became stale; collect again');
  if (!body || (body.errors !== undefined && (!Array.isArray(body.errors) || body.errors.length))) throw new Error('GraphQL usage request failed');
  const accounts = body.data?.viewer?.accounts;
  if (!Array.isArray(accounts) || accounts.length !== 1 || accounts[0].accountTag !== accountId) throw new Error('Account identity mismatch or incomplete usage response');
  const groups = accounts[0].d1AnalyticsAdaptiveGroups;
  if (!Array.isArray(groups) || groups.length >= GROUP_LIMIT) throw new Error('Missing or potentially truncated database groups; cloud permission denied');
  const seen = new Set(), databases = [];
  let rowsWritten = 0, rowsRead = 0;
  for (const group of groups) {
    const id = group?.dimensions?.databaseId;
    if (typeof id !== 'string' || !databasePattern.test(id) || group.dimensions.date !== date || seen.has(id)) throw new Error('Invalid, duplicate or mixed-day database group');
    seen.add(id);
    const writes = group.sum?.rowsWritten, reads = group.sum?.rowsRead;
    if (![writes, reads].every(n => Number.isSafeInteger(n) && n >= 0)) throw new Error('Invalid row counts');
    rowsWritten += writes; rowsRead += reads;
    if (!Number.isSafeInteger(rowsWritten) || !Number.isSafeInteger(rowsRead)) throw new Error('Usage total overflow');
    databases.push({databaseId: id, rowsWritten: writes, rowsRead: reads});
  }
  databases.sort((a, b) => b.rowsWritten - a.rowsWritten || a.databaseId.localeCompare(b.databaseId));
  return {format: 'aroyn-d1-budget-v1', complete: true, accountId, date, collectedAt, rowsWritten, rowsRead, source: 'Cloudflare account-wide D1 GraphQL', databases};
}

export async function collectD1Usage({accountId, token, fetchImpl = fetch, clock = Date.now}) {
  const startedAt = clock(), query = d1UsageQuery(accountId, startedAt);
  if (typeof token !== 'string' || !token.trim()) throw new Error('Analytics read token required in CLOUDFLARE_API_TOKEN');
  let response;
  try {
    response = await fetchImpl('https://api.cloudflare.com/client/v4/graphql', {
      method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + token},
      body: JSON.stringify({query}), signal: AbortSignal.timeout(10000), redirect: 'error'
    });
  } catch { throw new Error('Usage request unavailable; cloud permission denied'); }
  if (!response.ok) throw new Error('Usage HTTP request failed; cloud permission denied');
  let body;
  try { body = await response.json(); } catch { throw new Error('Invalid usage response; cloud permission denied'); }
  return normalizeD1Usage(body, {accountId, startedAt, collectedAt: clock()});
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    const output = process.argv[2];
    if (!output || process.argv.length !== 3 || !path.isAbsolute(output)) throw new Error('Usage: node tools/d1-account-usage.mjs ABSOLUTE_PRIVATE_REPORT_PATH');
    const report = await collectD1Usage({accountId: process.env.CLOUDFLARE_ACCOUNT_ID, token: process.env.CLOUDFLARE_API_TOKEN});
    await fs.mkdir(path.dirname(output), {recursive: true});
    await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
    console.log(JSON.stringify({date: report.date, rowsWritten: report.rowsWritten, rowsRead: report.rowsRead, databaseGroups: report.databases.length}));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {collectD1Usage, normalizeD1Usage, d1UsageQuery} from '../tools/d1-account-usage.mjs';
import {assertCloudTestBudget} from '../tools/cloud-test-budget.mjs';
const checks = [], pass = name => {checks.push({name, pass: true}); console.log('PASS ' + name);};
const accountId = 'a'.repeat(32), startedAt = Date.parse('2026-10-01T12:00:00Z');
const group = (id, writes) => ({dimensions: {date: '2026-10-01', databaseId: id}, sum: {rowsWritten: writes, rowsRead: 10}});
const groups = [group('11111111-1111-1111-1111-111111111111', 3027), group('22222222-2222-2222-2222-222222222222', 105242)];
const body = () => ({data: {viewer: {accounts: [{accountTag: accountId, d1AnalyticsAdaptiveGroups: structuredClone(groups)}]}}});
const parse = value => normalizeD1Usage(value, {accountId, startedAt, collectedAt: startedAt + 10});
try {
  const report = parse(body());
  assert.equal(report.rowsWritten, 108269); assert.equal(report.rowsRead, 20); assert.equal(report.databases[0].rowsWritten, 105242);
  assert.throws(() => assertCloudTestBudget(report, 250, startedAt + 10));
  const query = d1UsageQuery(accountId, startedAt);
  assert(query.includes('date_geq: "2026-10-01"')); assert(!query.includes('databaseId:'));
  pass('all database groups contribute, so a removed large fixture still blocks cloud permission');

  for (const mutate of [
    b => {b.errors = [{message: 'partial result'}];},
    b => {b.data.viewer.accounts[0].accountTag = 'b'.repeat(32);},
    b => {b.data.viewer.accounts.push(structuredClone(b.data.viewer.accounts[0]));},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups = null;},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups = Array(1000).fill(groups[0]);},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups.push(groups[0]);},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups[0].dimensions.date = '2026-09-30';},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups[0].sum.rowsWritten = -1;},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups[0].sum.rowsRead = 1.5;},
    b => {b.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups[0].sum.rowsWritten = Number.MAX_SAFE_INTEGER;}
  ]) {const b = body(); mutate(b); assert.throws(() => parse(b));}
  assert.throws(() => normalizeD1Usage(body(), {accountId, startedAt, collectedAt: startedAt + 300001}));
  assert.throws(() => normalizeD1Usage(body(), {accountId, startedAt, collectedAt: Date.parse('2026-10-02T00:00:00Z')}));
  pass('partial, mismatched, duplicate, truncated, malformed and stale/day-crossing metrics fail closed');

  let clockCalls = 0, calls = 0;
  const result = await collectD1Usage({accountId, token: 'synthetic-read-token', clock: () => startedAt + clockCalls++ * 10, fetchImpl: async (url, options) => {
    calls++; assert.equal(url, 'https://api.cloudflare.com/client/v4/graphql'); assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error'); assert.equal(options.headers.Authorization, 'Bearer synthetic-read-token');
    assert.equal(JSON.parse(options.body).query, query); return Response.json(body());
  }});
  assert.equal(calls, 1); assert(!JSON.stringify(result).includes('synthetic-read-token'));
  const low = body(); low.data.viewer.accounts[0].d1AnalyticsAdaptiveGroups = [groups[0]];
  assertCloudTestBudget(parse(low), 250, startedAt + 10);
  pass('one fixed read-only GraphQL request produces the budget format without token data');

  for (const fetchImpl of [async () => {throw new Error('network');}, async () => new Response('blocked', {status: 403}), async () => new Response('invalid JSON'), async () => Response.json({errors: [{message: 'denied'}]})]) {
    await assert.rejects(collectD1Usage({accountId, token: 'synthetic-read-token', clock: () => startedAt, fetchImpl}));
  }
  await assert.rejects(collectD1Usage({accountId, token: '', clock: () => startedAt, fetchImpl: async () => {throw new Error('must not fetch');}}));
  pass('missing credentials and unavailable or denied metrics never create a usage report');
} finally {await fs.writeFile(new URL('./usage-report-results.json', import.meta.url), JSON.stringify({checks, passed: checks.length === 4}, null, 2) + '\n');}

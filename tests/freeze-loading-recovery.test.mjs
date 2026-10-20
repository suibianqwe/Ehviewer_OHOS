import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = file => readFileSync(new URL('../entry/src/main/ets/' + file, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const erase = s => s.replace(/\b(?:private|export) /g, '')
  .replace(/: \(value: string\) => void/g, '').replace(/: \(\) => void/g, '')
  .replace(/new Promise<(?:void|string)>/g, 'new Promise')
  .replace(/: Promise<Map<string, string>>/g, '')
  .replace(/: Map<string, string>/g, '').replace(/new Map<string, string>/g, 'new Map')
  .replace(/: Promise<[^>]+>/g, '')
  .replace(/: (?:common.UIAbilityContext|EhTagSuggestion|ParsedTagDatabase|TagDatabaseDocument|TagDatabaseSection|GalleryPageLoadResult|GallerySite|CachedImageFile|CachePruneResult|CacheClearResult|WebDavClient|CloudGalleryIndex|ArrayBuffer|number|string|boolean|void)\b(?:\[\])?(?: \| null)?/g, '')
  .replace(/ as TagDatabaseDocument/g, '').replace(/: \(value: string\) => void/g, '');
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function func(source, name) {
  const start = source.search(new RegExp('^(?:export )?(?:async )?function ' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n}', start) + 2));
}
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
};

test('image cache commits asynchronously only after all bytes are written and the file is closed', async () => {
  const source = read('services/ReaderImageCache.ets');
  const events = [], bytes = [];
  let zeroWrite = false;
  const io = new Proxy({
    OpenMode: { CREATE: 1, TRUNC: 2, READ_WRITE: 4 },
    async open() { events.push('open'); return { fd: 1 }; },
    async write(_fd, buffer) {
      events.push('write');
      if (zeroWrite) return 0;
      const chunk = new Uint8Array(buffer).slice(0, 2);
      bytes.push(...chunk); return chunk.length;
    },
    async close() { events.push('close'); },
    async rename() { events.push('rename'); }
  }, { get(target, key) { assert.ok(!String(key).endsWith('Sync')); return target[key]; } });
  const write = Function('fs', func(source, 'writeImageCacheFile') + '\nreturn writeImageCacheFile;')(io);
  await write(new Uint8Array([1, 2, 3, 4, 5]).buffer, '/temporary', '/image');
  assert.deepEqual(bytes, [1, 2, 3, 4, 5]);
  assert.deepEqual(events, ['open', 'write', 'write', 'write', 'close', 'rename']);
  events.length = 0; zeroWrite = true;
  await assert.rejects(write(new Uint8Array([1]).buffer, '/temporary', '/image'), /Incomplete/);
  assert.deepEqual(events, ['open', 'write', 'close']);
  assert.match(source, /await finishImageBufferTransfer\(/);
  assert.match(read('services/CloudGalleryPageService.ets'), /await readerImageCache.storeBytes\(/);
});

test('failed tag database metadata commit restores previous database or keeps its recovery backup', async () => {
  const source = read('services/EhTagTranslationStore.ets');
  for (const rollbackFails of [false, true]) {
    const files = new Map([['/db/data', 'previous'], ['/db/meta', 'previous-meta']]);
    const io = {
      async mkdir() {}, async access(path) { return files.has(path); },
      async copyFile(from, to) { files.set(to, files.get(from)); },
      async rename(from, to) {
        if (from === '/db/meta.tmp' || (rollbackFails && from.endsWith('.backup'))) throw Error('disk error');
        files.set(to, files.get(from)); files.delete(from);
      }
    };
    const save = Function('fs', 'writeTextFile', 'removeFileQuietly',
      'return {' + method(source, 'saveOverride').replace(/: TagDatabaseMetadata/g, '') + '}.saveOverride;')(
      io, async (path, value) => files.set(path, value), async path => files.delete(path));
    await assert.rejects(save.call({ databaseDirectory: () => '/db', overridePath: () => '/db/data',
      metadataPath: () => '/db/meta' }, {}, { tsv: 'new', sha: 'sha', entries: [], sourceUpdatedAt: '' }), /database/);
    assert.equal(files.get(rollbackFails ? '/db/data.backup' : '/db/data'), 'previous');
    assert.equal(files.get('/db/meta'), 'previous-meta');
    assert.ok(!files.has('/db/data.tmp') && !files.has('/db/meta.tmp'));
  }
});

test('asynchronous check-in cookie capture cannot overwrite a changed account or expired attempt', async () => {
  const source = read('components/SessionScene.ets');
  for (const scenario of ['success', 'changed-account', 'expired']) {
    const first = deferred(); let stored = 'original', calls = 0, updates = 0;
    const capture = Function('webview', 'ehCookieStore', 'EhUrl', 'absorbCookieHeaderText', 'hasLoginCookie',
      func(source, 'captureEhAccountWebCookiesAsync').replace(/: \(\) => boolean/g, '') +
      '\nreturn captureEhAccountWebCookiesAsync;')(
      { WebCookieManager: { fetchCookie: async () => ++calls === 1 ? first.promise : 'member=1' } },
      { getStoredCookieHeader: () => stored, setCookieHeaderPreservingIgneous() { updates++; } },
      { HOST_E: 'e', HOST_EX: 'ex', FORUM_ORIGIN: 'forum', URL_SIGN_IN: 'login' },
      (_header, names, values) => { names.push('member'); values.push('1'); }, () => true);
    const pending = capture('news', () => scenario !== 'expired');
    if (scenario === 'changed-account') stored = 'other-account';
    first.resolve('member=1');
    assert.equal(await pending, scenario === 'success');
    assert.equal(updates, scenario === 'success' ? 1 : 0);
    assert.equal(calls, 5);
  }
});

const http = read('services/EhHttpClient.ets');
function client(api, html) {
  const tokens = [], keys = [];
  const request = Function('GallerySite', 'EhUrl', 'parseGalleryPageUrl', 'ehSpiderInfoStore',
    'getSharedShowKey', 'putSharedShowKey', 'return {' + method(http, 'loadGalleryPageFastNetwork') + '}.loadGalleryPageFastNetwork;')(
      { E: 'e' }, { getReferer: () => 'referer' }, () => ({ gid: 1, pageIndex: 0, pageToken: 'token' }),
      { putPageToken(...args) { tokens.push(args); } }, () => 'showkey', (...args) => keys.push(args));
  const state = { htmlCalls: 0, apiCalls: 0,
    async loadGalleryPageApi() { this.apiCalls++; return api; },
    async loadGalleryPageHtml() { this.htmlCalls++; return html; } };
  return { run: () => request.call(state, 'page', 'e', 'referer', true), state, tokens, keys };
}

test('healthy reader API remains one request; failures recover through HTML', async () => {
  const success = { ok: true, page: { pageUrl: 'page', showKey: 'key' } };
  const healthy = client(success, success);
  assert.equal(await healthy.run(), success);
  assert.equal(healthy.state.htmlCalls, 0);
  for (const statusCode of [0, 200, 403, 408, 429, 500, 503]) {
    const recovery = client({ ok: false, statusCode, message: 'API unavailable' }, success);
    assert.equal(await recovery.run(), success);
    assert.equal(recovery.state.apiCalls, 1);
    assert.equal(recovery.state.htmlCalls, 1);
  }
});

test('reader key mismatch clears stale keys; quota errors do not cause extra requests', async () => {
  const mismatch = client({ ok: false, message: 'Key mismatch', statusCode: 200 }, { ok: false, page: null });
  await mismatch.run();
  assert.equal(mismatch.keys[0][2], '');
  const quota = { ok: false, statusCode: 509, message: 'Image limit reached' };
  const denied = client(quota, {});
  assert.equal(await denied.run(), quota);
  assert.equal(denied.state.htmlCalls, 0);
});

test('cloud fallback has a real deadline, ignores late completion and handles rejection', async () => {
  const timers = new Map(); let sequence = 0;
  const source = read('services/ReaderLoadingRecovery.ets');
  const fallback = Function('setTimeout', 'clearTimeout', func(source, 'readerCloudPageWithFallback') +
    '\nreturn readerCloudPageWithFallback;')((callback) => { timers.set(++sequence, callback); return sequence; },
      id => timers.delete(id));
  const slow = deferred();
  const pending = fallback(slow.promise, 3000);
  [...timers.values()][0]();
  assert.equal(await pending, '');
  slow.resolve('/late.jpg');
  assert.equal(await pending, '');
  timers.clear();
  const fast = deferred();
  const ready = fallback(fast.promise, 3000);
  fast.resolve('/ready.jpg');
  assert.equal(await ready, '/ready.jpg');
  assert.equal(timers.size, 0);
  assert.equal(await fallback(Promise.reject(Error('offline')), 3000), '');
  const cloudOnly = deferred();
  assert.equal(fallback(cloudOnly.promise, 0), cloudOnly.promise);
  assert.equal(timers.size, 0);
});

test('concurrent cloud index requests share one scan and failures are briefly cached', async () => {
  const source = read('services/CloudGalleryPageService.ets');
  let now = 10000;
  const model = Function('Date', 'INDEX_TTL_MS', 'REFRESH_RETRY_MS',
    'return {' + method(source, 'resolveIndex') + '};')({ now: () => now }, 300000, 5000);
  const scan = deferred(); let calls = 0;
  Object.assign(model, { indexes: new Map(), pendingIndexes: new Map(), lastResolveAt: new Map(),
    resolveIndexInternal() { calls++; return scan.promise; } });
  const a = model.resolveIndex({}, 12, false);
  const b = model.resolveIndex({}, 12, false);
  assert.equal(calls, 1);
  scan.resolve(null);
  assert.deepEqual(await Promise.all([a, b]), [null, null]);
  assert.equal(await model.resolveIndex({}, 12, false), null);
  assert.equal(calls, 1);
  now += 5001;
  await model.resolveIndex({}, 12, false);
  assert.equal(calls, 2);
  assert.equal(model.pendingIndexes.size, 0);
});

const processing = read('services/TagTranslationProcessing.ets');
const processTags = Function(erase(processing.replace(/^export interface[\s\S]*?^}\n/gm, '')
  .replace(/^interface[\s\S]*?^}\n/gm, '')) + '\nreturn { parseTagTsv, prepareTagDatabase };')();

test('background tag parser preserves bundled TSV and validates new database before installation', () => {
  const tsv = readFileSync(new URL('../entry/src/main/resources/rawfile/ehtag_translations.tsv', import.meta.url), 'utf8');
  const tags = processTags.parseTagTsv(tsv);
  assert.ok(tags.length > 40000);
  assert.equal(tags[0].tag, tsv.split('\n')[0].split('\t')[1]);
  const sha = 'a'.repeat(40);
  const data = {};
  for (let i = 0; i < 10000; i++) data['tag' + i] = { name: '翻译' + i };
  const body = JSON.stringify({ head: { sha }, data: [{ namespace: 'parody', data }] });
  const parsed = processTags.prepareTagDatabase(body, sha);
  assert.equal(parsed.entries.length, 10000);
  assert.equal(processTags.parseTagTsv(parsed.tsv).length, 10000);
  assert.ok(parsed.entries.every(entry => entry.tag.startsWith('parody:')));
  assert.throws(() => processTags.prepareTagDatabase(body, 'b'.repeat(40)), /version mismatch/);
  assert.throws(() => processTags.prepareTagDatabase('{', sha), /invalid database JSON/);
  assert.throws(() => processTags.prepareTagDatabase(JSON.stringify({ head: { sha }, data: [] }), sha), /too few/);
});

test('tag database heavy parsing uses TaskPool and never falls back to synchronous disk reads', () => {
  const store = read('services/EhTagTranslationStore.ets');
  assert.match(store, /taskpool.execute\(prepareTagDatabaseTask/);
  assert.match(store, /taskpool.execute\(parseTagTsvTask/);
  assert.doesNotMatch(store, /\bfs\.\w+Sync\(|getRawFileContentSync|\.parseDatabaseDocument\(/);
  assert.match(read('services/TagTranslationTasks.ets'), /@Concurrent\s+export function prepareTagDatabaseTask/);
});

test('translation index construction yields regularly and does not publish a partial index', async () => {
  const store = read('services/EhTagTranslationStore.ets');
  let yields = 0;
  const build = Function('setTimeout', 'return {' + method(store, 'buildTranslationMap') + '}.buildTranslationMap;')(
    callback => { yields++; setImmediate(callback); });
  const entries = Array.from({ length: 2049 }, (_, i) => ({ tag: 'TAG' + i, translated: '' + i }));
  const index = await build(entries);
  assert.equal(yields, 4);
  assert.equal(index.size, entries.length);
  assert.equal(index.get('tag2048'), '2048');
});

test('cache maintenance is asynchronous, oldest-first and protects changing files and live downloads', async () => {
  const source = read('services/ReaderImageCache.ets');
  const files = new Map([
    ['/cache/old', { size: 10, mtime: 1 }], ['/cache/changed', { size: 20, mtime: 2 }],
    ['/cache/keep', { size: 30, mtime: 3 }], ['/cache/new', { size: 40, mtime: 4 }],
    ['/cache/live.part', { size: 20, mtime: 0 }], ['/cache/old.part', { size: 5, mtime: 0 }]
  ]);
  const reads = new Map(), removed = [];
  const fs = new Proxy({
    async listFile() { return [...files.keys()].map(path => path.substring(7)); },
    async stat(path) {
      const n = (reads.get(path) ?? 0) + 1; reads.set(path, n);
      const entry = files.get(path); if (!entry) throw Error('ENOENT');
      return { ...entry, mtime: path.endsWith('changed') && n > 1 ? 100 : entry.mtime, isDirectory: () => false };
    },
    async unlink(path) { removed.push(path); files.delete(path); }
  }, { get(target, key) { assert.ok(!String(key).endsWith('Sync')); return target[key]; } });
  const maintain = Function('fs', 'isImageTempPathActive', func(source, 'maintainImageCacheAsync') +
    '\nreturn maintainImageCacheAsync;')(fs, path => path.endsWith('live.part'));
  const result = await maintain(['/cache'], 70, '/cache/keep', false);
  assert.deepEqual(removed, ['/cache/old.part', '/cache/old', '/cache/new']);
  assert.deepEqual(result, { files: 2, bytes: 50, remainingBytes: 50 });
  assert.ok(files.has('/cache/keep'));
  assert.ok(files.has('/cache/live.part'));
  assert.ok(files.has('/cache/changed'));
});

test('cache maintenance jobs are serialized even after an earlier job fails', async () => {
  const source = read('services/ReaderImageCache.ets');
  const jobs = [];
  const model = Function('readerImageCacheDirectory', 'legacyReaderImageCacheDirectory', 'readerImageCacheLimitBytes',
    'maintainImageCacheAsync', 'return {' + method(source, 'pruneAsync') + ',' + method(source, 'clearAsync') + '};')(
      () => '/cache', () => '/legacy', () => 100,
      () => { const job = deferred(); jobs.push(job); return job.promise; });
  model.maintenance = Promise.resolve();
  const first = model.pruneAsync({}).catch(() => null);
  const second = model.clearAsync({});
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(jobs.length, 1);
  jobs[0].reject(Error('disk'));
  await first;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(jobs.length, 2);
  jobs[1].resolve({ files: 1, bytes: 20, remainingBytes: 0 });
  assert.equal((await second).bytes, 20);
});

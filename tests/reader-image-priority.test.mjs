import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
function erase(source) {
  return source.replace(/^import .*;\n/gm, '').replace(/^export interface [\s\S]*?^}\n/gm, '')
    .replace(/\b(?:export|private) /g, '').replace(/ implements rcp\.WriteFile/g, '')
    .replace(/: \(received: number, total: number\) => void/g, '')
    .replace(/: \(\) => void/g, '')
    .replace(/ as Record<string, string>/g, '').replace(/ as BusinessError/g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:ReaderTransferSink|fs\.File|ArrayBuffer|ReaderImageDemand|ReaderImageRequestControl|ReaderCancellableImageTransfer|rcp\.\w+|http\.HttpRequestOptions|number|string|boolean|void|Object)\b(?:\[\])?(?: \| undefined)?/g, '');
}
const controlSource = read('services/ReaderImageRequestControl.ets');
const { Control, visiblePriority, prefetchPriority } = Function(erase(controlSource) +
  '\nreturn { Control: ReaderImageRequestControl, visiblePriority: READER_VISIBLE_IMAGE_PRIORITY, prefetchPriority: READER_PREFETCH_IMAGE_PRIORITY };')();
const page = (index, gid = 10) => `https://example.org/s/token/${gid}-${index + 1}`;
const deferred = () => { let resolve, reject; const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; }); return { promise, resolve, reject }; };

test('current page and both visible spread pages outrank prefetch, then demote as the window moves', () => {
  const control = new Control(), owner = control.createOwner();
  control.update(owner, 10, [4, 5], 3);
  const first = control.acquire(page(4), 100), second = control.acquire(page(5), 100);
  const preload = control.acquire(page(7), 100);
  assert.equal(first.priority, visiblePriority);
  assert.equal(second.priority, visiblePriority);
  assert.equal(preload.priority, prefetchPriority);
  control.update(owner, 10, [7], 3);
  assert.equal(first.priority, prefetchPriority);
  assert.equal(preload.priority, visiblePriority);
  assert.equal(first.cancelled, false);
});

test('rapid jumps cancel out-of-range transfers once, including zero-preload and gallery changes', () => {
  const control = new Control(), owner = control.createOwner();
  control.update(owner, 10, [2], 2);
  const old = control.acquire(page(3), 100);
  let aborts = 0, changes = 0;
  old.abort = () => aborts++; old.onChange = () => changes++;
  control.update(owner, 10, [50], 2);
  control.update(owner, 10, [51], 2);
  assert.equal(old.cancelled, true); assert.equal(aborts, 1); assert.equal(changes, 1);
  control.update(owner, 10, [50, 51], 0);
  assert.equal(control.acquire(page(49), 100).cancelled, true);
  assert.equal(control.acquire(page(51), 100).priority, visiblePriority);
  const current = control.acquire(page(50), 100);
  control.update(owner, 11, [50], 2);
  assert.equal(current.cancelled, true);
});

test('leaving a reader cancels its work, but stale reader teardown cannot cancel the new reader', () => {
  const control = new Control(), oldOwner = control.createOwner(), newOwner = control.createOwner();
  control.update(oldOwner, 10, [0], 2);
  const old = control.acquire(page(0), 100);
  control.update(newOwner, 11, [0], 2);
  const fresh = control.acquire(page(0, 11), 100);
  assert.equal(old.cancelled, true);
  control.update(oldOwner, 10, [0], 2);
  assert.equal(fresh.cancelled, false);
  control.clear(oldOwner);
  assert.equal(fresh.cancelled, false);
  control.clear(newOwner);
  assert.equal(fresh.cancelled, true);
  assert.equal(control.wants(newOwner, 0), false);
});

test('shared preview references stay alive for a visible consumer; explicit saves are never cancelled', () => {
  const control = new Control(), owner = control.createOwner();
  control.update(owner, 10, [2], 3);
  const shared = control.acquire(page(2), 100), save = control.acquire(page(2), 100);
  control.attach(shared, page(5)); save.pinned = true;
  control.update(owner, 10, [5], 0);
  assert.equal(shared.cancelled, false); assert.equal(shared.priority, visiblePriority);
  control.update(owner, 10, [6], 0);
  assert.equal(shared.cancelled, true); assert.equal(save.cancelled, false);
  control.release(save);
  control.clear(owner);
  assert.equal(save.cancelled, false);
});

const adapterSource = read('services/ReaderCancellableImageTransfer.ets');
function adapter() {
  const active = new Map(), requests = [], cancellations = [], writes = [], closed = [];
  class Request { constructor(url, method, headers) { Object.assign(this, { url, method, headers }); } }
  const session = {
    fetch(request) { requests.push(request); const result = deferred(); active.set(request, result); return result.promise; },
    cancel(request) { cancellations.push(request); active.get(request)?.reject({ code: 1007900992 }); }
  };
  const fs = {
    OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    async open(path) { return { fd: path }; },
    async write(fd, buffer) { writes.push({ fd, buffer }); return buffer.byteLength; },
    async close(file) { closed.push(file.fd); }
  };
  const result = Function('rcp', 'deviceInfo', 'canIUse', 'fs', erase(adapterSource) +
    '\nreturn { transfer: readerCancellableImageTransfer, supports: supportsCancellableReaderTransfer };')(
    { Request, createSession: () => session }, { apiAvailable: () => true }, () => true, fs);
  return { ...result, active, requests, cancellations, writes, closed, fs,
    async ready() { for (let i = 0; i < 6; i++) await Promise.resolve(); },
    async body(index, size) {
      const request = requests[index];
      try {
        return await request.destination.file.write(new ArrayBuffer(size));
      } catch (_error) {
        active.get(request).reject({ code: 1007900023 });
        return -1;
      }
    }
  };
}

test('ordinary reader requests stop at the next body write without external native cancellation', async () => {
  const model = adapter(), control = new Control(), owner = control.createOwner();
  control.update(owner, 10, [0], 2);
  const demand = control.acquire(page(0), 100);
  const promise = model.transfer.download('https://image', { header: { Cookie: 'test' }, connectTimeout: 4500,
    readTimeout: 30000, usingProxy: false, dnsOverHttps: 'https://dns/dns-query', reuseConnections: false },
    '/image.part', demand, 1024, () => {});
  await model.ready();
  const request = model.requests[0];
  assert.deepEqual(request.headers, { Cookie: 'test' });
  assert.equal(request.destination.kind, 'file');
  assert.equal(await model.body(0, 10), 10);
  assert.equal(request.configuration.proxy, 'no-proxy');
  assert.equal(request.configuration.dns.dnsOverHttps.url, 'https://dns/dns-query');
  assert.equal(request.configuration.transfer.connectionReusePolicy, 'forbidden');
  control.update(owner, 10, [100], 2);
  assert.equal(await model.body(0, 10), -1);
  await assert.rejects(promise, /Reader image request cancelled/);
  assert.deepEqual(model.cancellations, []);
  assert.equal(model.writes.length, 1);
  assert.deepEqual(model.closed, ['/image.part']);
  assert.equal(demand.abort(), undefined);
});

test('cancelled requests cannot restart, reversing creates a fresh demand and late results cannot commit', async () => {
  const model = adapter(), control = new Control(), owner = control.createOwner();
  control.update(owner, 10, [0], 1);
  const old = control.acquire(page(0), 100);
  const oldPromise = model.transfer.download('image', { header: {} }, '/old.part', old, 1024, () => {});
  await model.ready();
  // Simulate native completion racing cancellation: ignore native cancel but mark the demand.
  old.abort = () => {};
  control.update(owner, 10, [20], 1);
  control.update(owner, 10, [0], 1);
  model.active.get(model.requests[0]).resolve({ statusCode: 200, headers: {} });
  await assert.rejects(oldPromise, /cancelled/);
  await assert.rejects(model.transfer.download('image', { header: {} }, '/old.part', old, 1024, () => {}), /cancelled/);
  assert.equal(model.requests.length, 1);
  const fresh = control.acquire(page(0), 100);
  const ready = model.transfer.download('image', { header: {} }, '/new.part', fresh, 1024, () => {});
  await model.ready();
  model.active.get(model.requests[1]).resolve({ statusCode: 200, headers: { 'content-type': 'image/png' } });
  assert.equal((await ready).statusCode, 200);
});

test('custom HTTP/SOCKS and fronting retain the existing transport; response limits remain enforced', async () => {
  const model = adapter();
  assert.equal(model.supports(false, { usingProxy: true }), true);
  assert.equal(model.supports(false, { usingProxy: false }), true);
  assert.equal(model.supports(true, { usingProxy: true }), false);
  assert.equal(model.supports(false, { usingSocks5Proxy: {} }), false);
  assert.equal(model.supports(false, { usingProxy: { host: 'proxy', port: 1234 } }), false);
  const demand = { cancelled: false, priority: visiblePriority, index: 0 };
  const pending = model.transfer.download('image', { header: {} }, '/large.part', demand, 10, () => {});
  await model.ready();
  assert.equal(await model.body(0, 11), -1);
  await assert.rejects(pending, /size limit/);
  assert.equal(model.writes.length, 0);
  assert.equal(model.cancellations.length, 0);
});

test('stream writes are ordered, handle short file writes and close only after pending IO drains', async () => {
  const model = adapter(), demand = { cancelled: false, priority: visiblePriority, index: 0 };
  const transfer = model.transfer.download('image', { header: {} }, '/ordered.part', demand, 100, () => {});
  await model.ready();
  const sizes = [];
  model.fs.write = async (_fd, buffer) => {
    sizes.push(buffer.byteLength);
    return sizes.length === 1 ? 3 : buffer.byteLength;
  };
  const sink = model.requests[0].destination.file;
  assert.deepEqual(await Promise.all([sink.write(new ArrayBuffer(8)), sink.write(new ArrayBuffer(4))]), [8, 4]);
  assert.deepEqual(sizes, [8, 5, 4]);
  model.active.get(model.requests[0]).resolve({ statusCode: 200, headers: {} });
  await transfer;
  assert.deepEqual(model.closed, ['/ordered.part']);

  const other = adapter(), write = deferred();
  const live = { cancelled: false, priority: visiblePriority, index: 1 };
  const pending = other.transfer.download('image', { header: {} }, '/pending.part', live, 100, () => {});
  await other.ready();
  other.fs.write = () => write.promise;
  const chunk = other.body(0, 8);
  await other.ready();
  live.cancelled = true; live.abort();
  const rejected = assert.rejects(pending, /cancelled/);
  other.active.get(other.requests[0]).reject({ code: 1007900028 });
  await other.ready();
  assert.deepEqual(other.closed, [], 'timeout must not close a file still being written');
  write.resolve(8);
  await chunk; await rejected;
  assert.deepEqual(other.closed, ['/pending.part']);
  assert.deepEqual(other.cancellations, []);
});

test('timeout and DNS errors preserve retry categories; cancellation while opening never starts fetch', async () => {
  for (const [code, message] of [[1007900028, /network timeout/], [1007900006, /DNS lookup failed/]]) {
    const model = adapter(), demand = { cancelled: false, priority: visiblePriority, index: 0 };
    const pending = model.transfer.download('image', { header: {} }, '/failed.part', demand, 100, () => {});
    await model.ready();
    model.active.get(model.requests[0]).reject({ code });
    await assert.rejects(pending, message);
    assert.deepEqual(model.closed, ['/failed.part']);
  }
  const model = adapter(), opening = deferred();
  model.fs.open = () => opening.promise;
  const demand = { cancelled: false, priority: visiblePriority, index: 0 };
  const pending = model.transfer.download('image', { header: {} }, '/opening.part', demand, 100, () => {});
  demand.cancelled = true; demand.abort();
  opening.resolve({ fd: '/opening.part' });
  await assert.rejects(pending, /cancelled/);
  assert.equal(model.requests.length, 0);
  assert.deepEqual(model.closed, ['/opening.part']);
  assert.doesNotMatch(adapterSource, /session\.cancel\(|session\.close\(/);
});

function cacheFunction(name) {
  const source = read('services/ReaderImageCache.ets');
  const start = source.indexOf('function ' + name + '(');
  return erase(source.slice(start, source.indexOf('\n}', start) + 2)).replace(/: WaitingImageSlot/g, '');
}

test('foreground reserve is bounded and unavailable to prefetch/download/background work', () => {
  const canDispatch = Function('activeImageDownloads', 'activeHathImageDownloads', 'READER_VISIBLE_IMAGE_PRIORITY',
    'MAX_DOH_HATH_IMAGE_DOWNLOADS', 'backgroundImageDispatchPaused', 'backgroundImageSettleUntil',
    'activeBackgroundImageDownloads', 'MAX_BACKGROUND_IMAGE_DOWNLOADS', cacheFunction('canDispatchImageSlot') +
    '\nreturn canDispatchImageSlot;')(3, 3, visiblePriority, 4, false, 0, 0, 8);
  assert.equal(canDispatch({ priority: visiblePriority, hath: true, background: false }, 3), true);
  assert.equal(canDispatch({ priority: prefetchPriority, hath: true, background: false }, 3), false);
  assert.equal(canDispatch({ priority: 10, hath: false, background: false }, 3), false);
  assert.equal(canDispatch({ priority: 0, hath: false, background: true }, 3), false);
  assert.match(read('services/ReaderImageCache.ets'), /activeImageDownloads < limit \+ 2/);
});

test('page changes synchronise demand windows in both readers and prevent stale recovery retries', () => {
  const host = read('components/ReaderHostScene.ets');
  assert.match(host, /readerImageRequestControl\.clear\(this\.readerImageWindowOwner\)/);
  assert.match(host, /lastError\.indexOf\('Reader image request cancelled'\)/);
  assert.match(host, /onVisiblePageIndexesChange:/);
  for (const view of ['ReaderImageViewport', 'ReaderContinuousImageItem']) {
    assert.match(read('components/reader/viewports/' + view + '.ets'), /readerPageUrl: this\.page\.pageUrl/);
  }
});

test('continuous scrolling reports every on-screen page, including when only the last visible page changes', () => {
  const source = read('components/ReaderScenes.ets');
  const start = source.indexOf('  private onContinuousScrollIndex(');
  const method = erase(source.slice(start, source.indexOf('\n  }', start) + 4));
  const reports = [], jumps = [];
  const model = Function('clearTimeout', 'return {' + method + '};')(() => {});
  Object.assign(model, { currentIndex: 2, continuousScrollTarget: -1, continuousScrollTimer: -1,
    continuousVisiblePageIndexes: [],
    pageIndexForVisualIndex: index => index, onVisiblePageIndexesChange: value => reports.push(value),
    scheduleImageProcessingPrefetch() {}, onJump: index => jumps.push(index) });
  model.onContinuousScrollIndex(2, 4);
  model.onContinuousScrollIndex(2, 5);
  assert.deepEqual(reports, [[2, 3, 4], [2, 3, 4, 5]]);
  assert.deepEqual(jumps, []);
  model.onContinuousScrollIndex(3, 5);
  assert.deepEqual(jumps, [3]);
  assert.deepEqual(model.continuousVisiblePageIndexes, [3, 4, 5]);
  model.continuousScrollTarget = 50;
  model.onContinuousScrollIndex(4, 6);
  assert.equal(reports.length, 3, 'old scroll callbacks cannot override a pending jump');
});

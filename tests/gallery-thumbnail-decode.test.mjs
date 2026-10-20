import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const cacheSource = read('services/GalleryThumbnailDecodeCache.ets');
const cardsSource = read('components/GalleryCards.ets');

function erase(source) {
  return source.replace(/^import .*\n/gm, '').replace(/\bexport |\bprivate /g, '')
    .replace(/: \(result: DecodedGalleryThumbnail \| null\) => void/g, '')
    .replace(/: \(\) => Promise<string>/g, '').replace(/: \(\) => void/g, '')
    .replace(/: Map<string, ThumbnailEntry>/g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:DecodedGalleryThumbnail|GalleryThumbnailLease|GalleryThumbnailDecodeCache|ThumbnailEntry|image\.PixelMap|image\.ImageSource|fs\.File|number|string|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '')
    .replace(/new (Map|Promise)<[^>]+>/g, 'new $1')
    .replace(/ as number/g, '');
}

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};

const tick = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
function harness(platform = {}) {
  const timers = [];
  const types = Function('image', 'fs', 'setTimeout', erase(cacheSource) +
    '\nreturn { GalleryThumbnailDecodeCache, DecodedGalleryThumbnail };')(
    platform.image ?? {}, platform.fs ?? {}, (fn) => { timers.push(fn); return timers.length; });
  const cache = new types.GalleryThumbnailDecodeCache();
  const decoded = (id, bytes = 350000) => Object.assign(new types.DecodedGalleryThumbnail(), {
    path: '/' + id, width: 250, height: 350, bytes,
    pixelMap: { id, releases: 0, async release() { this.releases++; } }
  });
  const flush = async () => {
    await tick();
    while (timers.length > 0) { timers.shift()(); await tick(); }
  };
  return { cache, decoded, flush, timers };
}

test('cover prefetch and all mounted consumers share one download/decode; work never starts in build', async () => {
  const { cache, decoded, flush } = harness();
  let loads = 0, decodes = 0;
  const result = decoded('cover');
  cache.decode = async () => { decodes++; return result; };
  const loader = async () => { loads++; return '/cover'; };
  for (let i = 0; i < 50; i++) cache.prefetch('cover', loader);
  const first = cache.acquire('cover', loader), second = cache.acquire('cover', loader);
  assert.equal(loads, 0);
  assert.equal(first.ready, null);
  await flush();
  assert.equal(loads, 1);
  assert.equal(decodes, 1);
  assert.equal(await first.pending, result);
  assert.equal(await second.pending, result);
  const warm = cache.acquire('cover', loader);
  assert.equal(warm.ready, result);
  first.release(); first.release(); second.release(); warm.release();
  assert.equal(cache.entries.get('cover').references, 0);
  assert.equal(result.pixelMap.releases, 0);
});

test('decode concurrency is bounded and mounted covers overtake offscreen prefetch', async () => {
  const { cache, decoded, flush } = harness();
  const started = [], work = [];
  cache.decode = (path) => { started.push(path); const job = deferred(); work.push(job); return job.promise; };
  cache.prefetch('a', async () => '/a');
  cache.prefetch('b', async () => '/b');
  cache.prefetch('c', async () => '/c');
  cache.acquire('visible', async () => '/visible');
  await flush();
  assert.deepEqual(started, ['/visible', '/a']);
  assert.equal(cache.activeDecodes, 2);
  work[0].resolve(decoded('visible'));
  await flush();
  assert.deepEqual(started, ['/visible', '/a', '/b']);
  assert.equal(cache.activeDecodes, 2);
  work[1].resolve(decoded('a')); work[2].resolve(decoded('b'));
  await flush();
  work[3].resolve(decoded('c'));
  await flush();
  assert.equal(cache.activeDecodes, 0);
});

test('rapid scrolling bounds speculative requests without dropping mounted requests', async () => {
  const { cache } = harness();
  const never = () => new Promise(() => {});
  for (let i = 0; i < 1000; i++) cache.prefetch(String(i), never);
  assert.equal(cache.entries.size, 32);
  cache.acquire('visible', never);
  assert.equal(cache.entries.size, 33);
});

test('failed downloads do not poison later retries', async () => {
  const { cache, decoded, flush } = harness();
  const failed = cache.acquire('x', async () => { throw Error('offline'); });
  await flush();
  assert.equal(await failed.pending, null);
  assert.equal(cache.entries.has('x'), false);
  cache.decode = async () => decoded('x');
  const retry = cache.acquire('x', async () => '/x');
  await flush();
  assert.equal((await retry.pending).path, '/x');
  failed.release(); retry.release();
});

test('render failures decode again without evicting newer retries or releasing other consumers', async () => {
  const { cache, decoded, flush } = harness();
  const results = [];
  cache.decode = async () => { const result = decoded(String(results.length)); results.push(result); return result; };
  const first = cache.acquire('cover', async () => '/cover');
  const other = cache.acquire('cover', async () => '/cover');
  await flush();
  first.invalidate(); first.release();
  assert.equal(results[0].pixelMap.releases, 0);
  const retry = cache.acquire('cover', async () => '/cover');
  await flush();
  assert.equal(results.length, 2);
  other.invalidate(); other.release();
  assert.equal(results[0].pixelMap.releases, 1);
  assert.equal(cache.entries.get('cover').result, results[1]);
  first.invalidate();
  assert.equal(cache.entries.get('cover').result, results[1]);
  retry.release(); cache.clear();
  assert.equal(results[1].pixelMap.releases, 1);
});

test('idle pixel memory is bounded; mounted PixelMaps are pinned and released only once', async () => {
  const { cache, decoded, flush } = harness();
  const results = [];
  cache.decode = async (path) => { const result = decoded(path, 16 * 1024 * 1024); results.push(result); return result; };
  const pinned = cache.acquire('pinned', async () => '/pinned');
  await flush();
  cache.prefetch('a', async () => '/a'); await flush();
  cache.prefetch('b', async () => '/b'); await flush();
  assert.equal(results[0].pixelMap.releases, 0);
  assert.equal(results[1].pixelMap.releases, 1);
  assert.equal(results[2].pixelMap.releases, 0);
  pinned.release(); pinned.release();
  assert.equal(results[2].pixelMap.releases, 1);
  cache.clear();
  assert.equal(results[0].pixelMap.releases, 1);
});

test('LRU retains recently used covers and caps even tiny cached entries', async () => {
  const { cache, decoded, flush } = harness();
  cache.decode = async (path) => decoded(path, 1);
  for (let i = 0; i < 64; i++) { cache.prefetch(String(i), async () => '/' + i); await flush(); }
  cache.prefetch('0', async () => { throw Error('must stay cached'); });
  cache.prefetch('64', async () => '/64'); await flush();
  assert.equal(cache.entries.size, 64);
  assert.equal(cache.entries.has('0'), true);
  assert.equal(cache.entries.has('1'), false);
});

test('clearing cache discards late prefetch results but keeps a mounted cover alive', async () => {
  const { cache, decoded, flush } = harness();
  const active = decoded('active');
  cache.decode = async () => active;
  const lease = cache.acquire('active', async () => '/active'); await flush();
  const job = deferred(), late = decoded('late');
  cache.decode = () => job.promise;
  cache.prefetch('late', async () => '/late'); await flush();
  cache.clear();
  assert.equal(active.pixelMap.releases, 0);
  job.resolve(late); await flush();
  assert.equal(late.pixelMap.releases, 1);
  assert.equal(cache.entries.size, 0);
  lease.release();
  assert.equal(active.pixelMap.releases, 1);
});

function platform({ frames = 1, mime = 'image/webp', width = 250, height = 350, fail = false } = {}) {
  const calls = [];
  const pixelMap = { getPixelBytesNumber: () => width * height * 4 };
  const source = {
    async getImageInfo() { calls.push('info'); return { size: { width, height }, mimeType: mime }; },
    async getFrameCount() { calls.push('frames'); return frames; },
    async createPixelMap(options) {
      calls.push(['decode', options]); if (fail) throw Error('codec'); return pixelMap;
    },
    async release() { calls.push('release-source'); }
  };
  return { calls, pixelMap,
    image: { DecodingDynamicRange: { AUTO: 'AUTO' }, createImageSource(fd) { calls.push(['source', fd]); return source; } },
    fs: { OpenMode: { READ_ONLY: 0 }, async open(path) { calls.push(['open', path]); return { fd: 7 }; },
      async close(file) { calls.push(['close', file.fd]); } }
  };
}

test('decode uses async file open, metadata and full-quality PixelMap; closes source before file', async () => {
  const io = platform(); const { cache } = harness(io);
  const result = await cache.decode('file:///cover.webp');
  assert.equal(result.pixelMap, io.pixelMap);
  assert.deepEqual(io.calls, [['open', '/cover.webp'], ['source', 7], 'info', 'frames',
    ['decode', { editable: false, desiredDynamicRange: 'AUTO' }], 'release-source', ['close', 7]]);
  assert.equal(result.width, 250);
  assert.equal(result.height, 350);
});

test('animated, vector and unusually large covers retain the native async loader without quality loss', async () => {
  for (const options of [{ frames: 3 }, { mime: 'image/svg+xml' }, { width: 3000, height: 3000 }]) {
    const io = platform(options); const { cache } = harness(io);
    const result = await cache.decode('/special');
    assert.equal(result.path, '/special');
    assert.equal(result.pixelMap, undefined);
    assert.equal(io.calls.some((call) => Array.isArray(call) && call[0] === 'decode'), false);
    assert.deepEqual(io.calls.at(-1), ['close', 7]);
  }
});

test('codec failures fall back without leaking file handles or ImageSources', async () => {
  const io = platform({ fail: true }); const { cache } = harness(io);
  const result = await cache.decode('/cover');
  assert.equal(result.path, '/cover');
  assert.equal(result.pixelMap, undefined);
  assert.deepEqual(io.calls.slice(-2), ['release-source', ['close', 7]]);
});

test('a PixelMap with unavailable memory accounting is released before the native fallback', async () => {
  const io = platform(); let releases = 0;
  io.pixelMap.getPixelBytesNumber = () => { throw Error('pixel metadata unavailable'); };
  io.pixelMap.release = async () => { releases++; };
  const { cache } = harness(io);
  const result = await cache.decode('/cover');
  assert.equal(result.pixelMap, undefined);
  assert.equal(result.bytes, 0);
  assert.equal(result.path, '/cover');
  assert.equal(releases, 1);
  assert.deepEqual(io.calls.slice(-2), ['release-source', ['close', 7]]);
});

function component() {
  const names = ['aboutToAppear', 'aboutToDisappear', 'onUrlChange', 'releaseThumbnail', 'cacheThumb',
    'applyThumbnail', 'reportThumbnailAspectRatio', 'onThumbnailError'];
  const source = cardsSource.slice(cardsSource.indexOf('export struct GalleryThumb {'));
  const methods = names.map((name) => {
    const start = source.search(new RegExp('^  (?:private )?' + name + '\\(', 'm'));
    return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
  });
  const leases = [], timers = new Map(); let nextTimer = 0;
  const model = Function('acquireThumbnailImage', 'readerLocalImageSource', 'rememberGalleryThumbAspectRatio',
    'normalizedThumbnailAspectRatio', 'setTimeout', 'clearTimeout', 'return {' + methods.join(',\n') + '};')(
    () => { const job = deferred(); const lease = { ready: null, pending: job.promise, releases: 0,
      invalidations: 0, invalidate() { this.invalidations++; },
      release() { this.releases++; }, resolve: job.resolve }; leases.push(lease); return lease; },
    (path) => path, () => {}, (w, h) => w / h,
    (fn) => { const id = ++nextTimer; timers.set(id, fn); return id; }, (id) => timers.delete(id));
  return Object.assign(model, { url: 'a', cachedUrl: '', mounted: false, thumbnailRequest: 0,
    thumbnailLease: null, thumbnailSource: '', retryTimer: -1, imageRetryCount: 0, reports: [],
    onImageAspectRatio(value) { this.reports.push(value); }, leases, timers,
    flush() { while (timers.size) { const [id, fn] = timers.entries().next().value; timers.delete(id); fn(); } } });
}

test('recycled cover cannot receive an earlier URL result or stale dimensions', async () => {
  const state = component(); state.aboutToAppear();
  state.url = 'b'; state.onUrlChange();
  assert.equal(state.leases[0].releases, 1);
  state.leases[1].resolve({ path: '/b', width: 200, height: 300 }); await tick();
  state.leases[0].resolve({ path: '/a', width: 900, height: 100 }); await tick();
  assert.equal(state.thumbnailSource, '/b');
  state.flush();
  assert.deepEqual(state.reports, [2 / 3]);
});

test('disappearing cover releases its lease and ignores late results and scheduled retries', async () => {
  const state = component(); state.aboutToAppear(); state.onThumbnailError(); state.aboutToDisappear();
  state.leases[0].resolve({ path: '/a', width: 200, height: 300 }); await tick(); state.flush();
  assert.equal(state.thumbnailSource, '');
  assert.equal(state.leases[0].releases, 1);
  assert.equal(state.leases.length, 1);
  assert.deepEqual(state.reports, []);
});

test('repeated updates for the same URL preserve the displayed cover and pending request', async () => {
  const state = component(); state.aboutToAppear(); state.onUrlChange();
  assert.equal(state.leases.length, 1);
  const pixelMap = {};
  state.leases[0].resolve({ pixelMap, path: '/a', width: 200, height: 300 }); await tick();
  for (let i = 0; i < 20; i++) state.onUrlChange();
  assert.equal(state.thumbnailSource, pixelMap);
  assert.equal(state.leases.length, 1);
});

test('a mounted cover invalidates failed decoded data before scheduling a bounded retry', async () => {
  const state = component(); state.aboutToAppear();
  for (let i = 0; i < 3; i++) {
    const lease = state.leases[i];
    lease.resolve({ pixelMap: {}, path: '/a', width: 200, height: 300 }); await tick();
    state.onThumbnailError(); state.onThumbnailError(); state.flush();
    assert.equal(lease.invalidations, 1);
    assert.equal(lease.releases, i < 2 ? 1 : 0);
  }
  assert.equal(state.leases.length, 3);
  assert.equal(state.loadFailed, true);
  state.aboutToDisappear();
  assert.equal(state.leases[2].releases, 1);
});

test('all shared covers display decoded pixels or async fallbacks; range prefetch also decodes', () => {
  const componentSource = cardsSource.slice(cardsSource.indexOf('export struct GalleryThumb {'),
    cardsSource.indexOf('export struct GalleryThumbCard {'));
  assert.match(componentSource, /Image\(this.thumbnailSource\)/);
  assert.match(componentSource, /\.syncLoad\(false\)/);
  assert.doesNotMatch(componentSource, /syncLoad\(true\)|cacheThumbnailImage\(/);
  assert.match(read('shared/EhShared.ets'), /galleryThumbnailDecodeCache.prefetch\(url/);
  assert.doesNotMatch(cacheSource, /getImageInfoSync|createPixelMapSync|openSync/);
  const sizeReader = read('components/GalleryListSupport.ets').split('export async function readThumbnailImageSize')[1]
    .split('export interface GalleryListSceneCache')[0];
  assert.match(sizeReader, /await source.getImageInfo\(\)/);
  assert.doesNotMatch(sizeReader, /getImageInfoSync/);
});

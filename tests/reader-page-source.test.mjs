import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const guardSource = read('services/ReaderPageSourceGuard.ets');
const cacheSource = read('services/ReaderImageCache.ets');
const hostSource = read('components/ReaderHostScene.ets');
function erase(s) {
  return s.replace(/^import [\s\S]*?;\n/gm, '').replace(/\bprivate |\bexport /g, '')
    .replace(/: Map<string, Promise<boolean>>/g, '').replace(/: Map<string, Promise<string>>/g, '')
    .replace(/: Map<string, string>/g, '').replace(/new Map<string, Promise<(boolean|string)>>/g, 'new Map')
    .replace(/new Map<string, string>/g, 'new Map').replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:common\.UIAbilityContext|ReaderPageSourceGuard|GalleryPreview|GalleryPage|number|string|boolean|void)\b(?:\[\])?(?: \| (?:undefined|null))?/g, '');
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
const preview = { index: 1, pageUrl: 'https://example.test/s/key/123-2', imageUrl: 'https://thumb.test/sheet.webp',
  width: 200, height: 300, xOffset: 200, yOffset: 0 };
const previews = [preview, { ...preview, index: 19, xOffset: 3800 }];
function setup() {
  const files = new Map(); let clock = 1;
  const put = (path, digest, size = 321220, width = 4000, height = 300) => {
    files.set(path, { digest, size, width, height, mtime: clock++ });
  };
  const calls = { hashes: [], downloads: [], moves: [], copies: [], info: [] };
  let cachedReference = '/sheet.webp', offline = false, failInstall = false;
  const stat = async path => { const data = files.get(path); if (!data) throw Error('ENOENT'); return { ...data }; };
  const io = { stat, access: async path => files.has(path),
    async copyFile(from, to) { calls.copies.push([from, to]); files.set(to, { ...await stat(from), mtime: clock++ }); },
    async rename(from, to) { calls.moves.push([from, to]); if (failInstall && from.endsWith('.part')) throw Error('disk');
      const data = await stat(from); files.set(to, data); files.delete(from); },
    async unlink(path) { files.delete(path); }
  };
  const cache = { getCachedPath: () => files.has(cachedReference) ? cachedReference : '',
    async ensureCached(...args) { calls.downloads.push(args); if (offline) throw Error('offline');
      put('/sheet.webp', 'SHEET'); return '/sheet.webp'; } };
  const image = { createImageSource(path) { return { async getImageInfo() { calls.info.push(path);
    const data = await stat(path); return { size: { width: data.width, height: data.height } }; }, async release() {} }; } };
  const types = Function('fs', 'hash', 'image', 'hilog', 'readerImageCache', 'IMAGE_DOWNLOAD_PRIORITY_READER',
    erase(guardSource) + '\nreturn { ReaderPageSourceGuard, cloudReaderImageKey };')(
      io, { async hash(path, algorithm) { assert.equal(algorithm, 'sha256'); calls.hashes.push(path); return (await stat(path)).digest; } },
      image, { warn() {}, info() {} }, cache, 100);
  const guard = new types.ReaderPageSourceGuard();
  return { guard, put, files, calls, cloudKey: types.cloudReaderImageKey,
    check: (path = '/page.webp') => guard.isPreview({}, path, preview, previews, preview.pageUrl),
    set offline(value) { offline = value; }, set failInstall(value) { failInstall = value; } };
}

test('legacy preview sheet is rejected by exact bytes, even after migration changed its filename', async () => {
  const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'SHEET');
  assert.equal(await h.check(), true);
  assert.equal(h.guard.rejected.get('/page.webp'), 'SHEET');
  assert.deepEqual(h.calls.hashes, ['/page.webp', '/sheet.webp']);
  assert.equal(h.calls.moves.length, 0, 'validation must not mutate downloads');
});

test('same-sized panoramas and small real pages are preserved when bytes differ', async () => {
  const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'REAL');
  assert.equal(await h.check(), false);
  h.put('/page.webp', 'SMALL', 1000, 200, 300);
  assert.equal(await h.check(), false);
  assert.equal(h.guard.rejected.size, 0);
  assert.equal(h.calls.moves.length, 0);
});

test('concurrent reads share validation and modified files are checked again', async () => {
  const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'REAL');
  assert.deepEqual(await Promise.all(Array.from({ length: 30 }, () => h.check())), Array(30).fill(false));
  assert.equal(h.calls.hashes.length, 2);
  h.put('/page.webp', 'SHEET');
  assert.equal(await h.check(), true);
  assert.equal(h.calls.hashes.length, 4);
});

test('ordinary portraits do not download missing sprite references and all metadata reads are async', async () => {
  const h = setup(); h.put('/page.webp', 'REAL', 800000, 1280, 1790);
  assert.equal(await h.check(), false);
  assert.equal(h.calls.downloads.length, 0);
  assert.equal(h.calls.hashes.length, 0);
  assert.doesNotMatch(guardSource, /getImageInfoSync|readSync|hashSync/);
});

test('missing preview is fetched for an unverified sheet; offline failure preserves the file and is retryable', async () => {
  const h = setup(); h.put('/page.webp', 'SHEET'); h.offline = true;
  assert.equal(await h.check(), false);
  assert.equal(h.files.get('/page.webp').digest, 'SHEET');
  assert.equal(h.guard.checks.size, 0);
  h.offline = false;
  assert.equal(await h.check(), true);
  assert.equal(h.calls.downloads.length, 2);
  assert.equal(h.calls.downloads[1][3], 100, 'page validation must run while background thumbnails are paused');
});

test('a queued thumbnail needed by the reader escapes the background pause when promoted', () => {
  const extract = name => {
    const start = cacheSource.indexOf('function ' + name + '(');
    return erase(cacheSource.slice(start, cacheSource.indexOf('\n}', start) + 2))
      .replace(/: WaitingImageSlot/g, '');
  };
  const waiting = [
    { key: 'required-sheet', priority: 0, background: true, hath: false },
    { key: 'unrelated-cover', priority: 0, background: true, hath: false }
  ];
  const dispatched = [];
  const scheduler = Function('WAITING_IMAGE_SLOTS', 'dispatchWaitingImageSlots',
    `const IMAGE_DOWNLOAD_PRIORITY_BACKGROUND = 0, MAX_DOH_HATH_IMAGE_DOWNLOADS = 4,
      MAX_BACKGROUND_IMAGE_DOWNLOADS = 8, activeHathImageDownloads = 0,
      activeImageDownloads = 0, READER_VISIBLE_IMAGE_PRIORITY = 200,
      activeBackgroundImageDownloads = 0, backgroundImageDispatchPaused = true,
      backgroundImageSettleUntil = 0;
      ${['isBackgroundImagePriority', 'canDispatchImageSlot', 'promoteImageSlot'].map(extract).join('\n')}
      return { canDispatchImageSlot, promoteImageSlot };`)(waiting,
        () => dispatched.push(...waiting.filter(slot => scheduler.canDispatchImageSlot(slot, 3))));
  assert.equal(scheduler.canDispatchImageSlot(waiting[0], 3), false);
  scheduler.promoteImageSlot('required-sheet', 100);
  assert.deepEqual(dispatched.map(slot => slot.key), ['required-sheet']);
  assert.equal(scheduler.canDispatchImageSlot(waiting[1], 3), false);
});

test('repair verifies the replacement, retains the original and keeps its actual format extension', async () => {
  const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'SHEET'); h.put('/real.jpg', 'REAL', 900000);
  assert.equal(await h.check(), true);
  const [a, b] = await Promise.all([h.guard.repairDownload('/page.webp', '/real.jpg'), h.guard.repairDownload('/page.webp', '/real.jpg')]);
  assert.equal(a, '/page.jpg'); assert.equal(b, a);
  assert.equal(h.files.get('/page.jpg').digest, 'REAL');
  assert.equal(h.files.has('/page.webp'), false);
  const backups = [...h.files.keys()].filter(path => path.includes('.preview-backup-'));
  assert.equal(backups.length, 1);
  assert.equal(h.files.get(backups[0]).digest, 'SHEET');
  assert.equal(h.calls.copies.length, 1);
});

test('failed replacement rolls back and leaves the verified source available', async () => {
  const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'SHEET'); h.put('/real.webp', 'REAL');
  await h.check(); h.failInstall = true;
  assert.equal(await h.guard.repairDownload('/page.webp', '/real.webp'), '/real.webp');
  assert.equal(h.files.get('/page.webp').digest, 'SHEET');
  assert.equal([...h.files.keys()].some(path => path.includes('.preview-backup-')), false);
});

test('changed files, unverified files and identical replacements are never overwritten', async () => {
  for (const mode of ['unverified', 'changed', 'identical', 'existing-format']) {
    const h = setup(); h.put('/sheet.webp', 'SHEET'); h.put('/page.webp', 'SHEET'); h.put('/real.jpg', 'REAL');
    if (mode !== 'unverified') await h.check();
    if (mode === 'changed') h.put('/page.webp', 'USER_EDIT');
    if (mode === 'identical') h.put('/real.jpg', 'SHEET');
    if (mode === 'existing-format') h.put('/page.jpg', 'USER_EDIT');
    assert.equal(await h.guard.repairDownload('/page.webp', '/real.jpg'), '/real.jpg');
    assert.equal(h.calls.moves.length, 0, mode);
    assert.equal(h.calls.copies.length, 0, mode);
  }
});

function imageCache(files) {
  const func = name => { const start = cacheSource.indexOf('function ' + name + '(');
    return erase(cacheSource.slice(start, cacheSource.indexOf('\n}', start) + 2)); };
  const moves = [];
  const cache = Function('readerImageCacheDirectory', 'legacyReaderImageCacheDirectory', 'isUsableCachedImage', 'migrateLegacyImageCacheFile',
    ['stableImageKey', 'normalizeImageCacheKey', 'imageExtension', 'explicitImageExtension'].map(func).join('\n') +
    '\nreturn {' + ['getCachedPath', 'pathFor', 'legacyPathFor', 'pathForExtension', 'pathCandidates', 'migrateExistingCache']
      .map(name => method(cacheSource, name)).join(',\n') + '};')(
        () => '/current', () => '/legacy', path => files.has(path), (from, to) => {
          moves.push([from, to]); files.set(to, files.get(from)); files.delete(from); return true;
        });
  return { cache, moves };
}

test('keyed page lookup cannot migrate a URL-only preview; matching legacy page identity still migrates', () => {
  const files = new Map(); const { cache, moves } = imageCache(files);
  const url = preview.imageUrl, pageKey = preview.pageUrl + '#image';
  const thumbPath = cache.pathFor({}, url);
  files.set(thumbPath, 'SHEET');
  assert.equal(cache.getCachedPath({}, url, pageKey), '');
  assert.equal(files.get(thumbPath), 'SHEET'); assert.equal(moves.length, 0);
  files.set(cache.legacyPathFor({}, url, pageKey), 'FULL');
  const fullPath = cache.getCachedPath({}, url, pageKey);
  assert.equal(files.get(fullPath), 'FULL');
  assert.equal(files.get(thumbPath), 'SHEET'); assert.equal(moves.length, 1);
});

test('cloud read ignores both thumbnail and contaminated network-page caches', async () => {
  const h = setup(); const files = new Map(); const { cache } = imageCache(files);
  files.set(cache.pathFor({}, preview.imageUrl), 'SHEET');
  files.set(cache.pathFor({}, preview.imageUrl, preview.pageUrl + '#image'), 'SHEET');
  const requests = [], applied = [];
  const cloudRead = Function('cloudGalleryPageService', 'ehDownloadStore', 'ehDownloadFileStore', 'cloudReaderImageKey',
    'readerImageCache', 'readerPageSourceGuard', 'readerCloudPageWithFallback',
    'return {' + method(hostSource, 'tryUseCloudPage') + '}.tryUseCloudPage;')(
      { hasDownloadsProfile: () => true, async fetchPage(...args) { requests.push(args); return '/full.webp'; } },
      { contains: () => true }, { findPageImage: () => '' }, h.cloudKey, cache, { isPreview: async () => false },
      request => request);
  const state = { detail: { gid: 123, previewSet: previews }, readerContext: () => ({}), readerSceneActive: true,
    readerPreviewForIndex: () => preview, detailRequestUrl: 'https://example.test/g/123/',
    applyCloudPage(index, page, path) { applied.push({ index, page, path }); return true; } };
  assert.equal(await cloudRead.call(state, 1), true);
  assert.equal(requests.length, 1);
  assert.equal(requests[0][3], 'ehviewer://cloud-page/v2/123/1');
  assert.equal(requests[0][4], requests[0][3]);
  assert.equal(applied[0].page.imageUrl, '');
  assert.equal(applied[0].path, '/full.webp');
  assert.notEqual(h.cloudKey(123, 1), h.cloudKey(124, 1));
  assert.notEqual(h.cloudKey(123, 1), h.cloudKey(123, 2));
});

test('downloaded pages carry no thumbnail URL and cannot contaminate the network page cache', async () => {
  const stored = [];
  const useLocal = Function('ehDownloadFileStore', 'readerPageSourceGuard', 'cloneGalleryPage',
    'return {' + method(hostSource, 'tryUseDownloadedPage') + '}.tryUseDownloadedPage;')(
      { findPageImage: () => '/download.webp' }, { isPreview: async () => false }, p => ({ ...p }));
  const state = { detail: { gid: 123, previewSet: previews }, readerContext: () => ({}), readerSceneActive: true,
    detailRequestUrl: '', pageIndex: 1, renderVersion: 0, setReaderPage: (_index, p) => stored.push(p),
    prepareDownloadedSpreadSizes: async () => {} };
  assert.equal(await useLocal.call(state, 1, preview), true);
  assert.equal(stored[0].imageUrl, '');
  assert.equal(stored[0].cachedImagePath, '/download.webp');
  assert.doesNotMatch(method(hostSource, 'tryUseDownloadedPage'), /galleryPageCache.put/);
  assert.match(method(read('services/GalleryPageCache.ets'), 'put'), /page.imageUrl/);
});

test('late local validation cannot overwrite another gallery or an exited reader', async () => {
  let finish;
  const useLocal = Function('ehDownloadFileStore', 'readerPageSourceGuard', 'cloneGalleryPage',
    'return {' + method(hostSource, 'tryUseDownloadedPage') + '}.tryUseDownloadedPage;')(
      { findPageImage: () => '/download.webp' }, { isPreview: () => new Promise(resolve => { finish = resolve; }) }, p => p);
  for (const change of [state => { state.detail.gid = 456; }, state => { state.readerSceneActive = false; }]) {
    const state = { detail: { gid: 123, previewSet: previews }, readerContext: () => ({}), readerSceneActive: true,
      setReaderPage() { assert.fail('stale result'); } };
    const pending = useLocal.call(state, 1, preview); change(state); finish(false);
    assert.equal(await pending, false);
  }
});

function pageLoader({ damaged = true, failDownload = false } = {}) {
  const source = read('shared/EhShared.ets');
  const start = source.indexOf('export async function cacheReaderImageForPage(');
  const code = erase(source.slice(start, source.indexOf('\n}', start) + 2))
    .replace(/onReady: \(page\) => void/g, 'onReady')
    .replace(/gallery\?: GalleryDetail/g, 'gallery').replace(/index\?/g, 'index')
    .replace(/abilityContext\?/g, 'abilityContext').replace(/onError\?: \(message\) => void/g, 'onError')
    .replace(/options\?: ImageDownloadOptions/g, 'options');
  const calls = [], displayed = [], errors = [];
  const loader = Function('readerPageSourceGuard', 'readerImageCache', 'ehDownloadFileStore', 'getAbilityContext',
    'cloneGalleryPageWithCache', 'readerPageImageCacheKey', 'IMAGE_DOWNLOAD_PRIORITY_READER', code + '\nreturn cacheReaderImageForPage;')(
      { async isPreview(_ctx, path) { calls.push(['check', path]); return damaged && ['local', 'cached'].includes(path); },
        async repairDownload(path, replacement) { calls.push(['repair', path, replacement]); return 'repaired'; } },
      { getCachedPath: () => 'cached', removeCached(...args) { calls.push(['remove', ...args]); },
        async ensureCached(...args) { calls.push(['fetch', ...args]); if (failDownload) throw Error('offline'); return 'full'; } },
      { findPageImage: () => 'local' }, () => ({}), (p, path) => ({ ...p, cachedImagePath: path }), p => p.pageUrl + '#image', 100);
  return { calls, displayed, errors, run: () => loader({ pageUrl: preview.pageUrl, imageUrl: 'https://images.test/full.webp' },
    page => displayed.push(page), { previewSet: previews }, 1, {}, err => errors.push(err)) };
}

test('reader replaces contaminated cache and download only after the real page arrives', async () => {
  const h = pageLoader(); await h.run();
  assert.equal(h.displayed.length, 1);
  assert.equal(h.displayed[0].cachedImagePath, 'repaired');
  assert.ok(h.calls.findIndex(c => c[0] === 'fetch') < h.calls.findIndex(c => c[0] === 'repair'));
  assert.deepEqual(h.calls.filter(c => c[0] === 'repair'), [['repair', 'local', 'full']]);
  assert.equal(h.errors.length, 0);
});

test('failed full-page download preserves the old downloaded file and reports the failure', async () => {
  const h = pageLoader({ failDownload: true }); await h.run();
  assert.equal(h.displayed.length, 0);
  assert.equal(h.calls.some(c => c[0] === 'repair'), false);
  assert.match(h.errors[0], /offline/);
});

test('healthy offline download avoids the page cache and image network request', async () => {
  const h = pageLoader({ damaged: false }); await h.run();
  assert.equal(h.displayed[0].cachedImagePath, 'local');
  assert.deepEqual(h.calls, [['check', 'local']]);
});

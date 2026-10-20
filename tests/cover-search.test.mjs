import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const support = read('services/CoverSearchSupport.ets');
const host = read('components/GalleryDetailHostScene.ets');
const gallery = read('components/GalleryScenes.ets');
const detailSupport = read('services/GalleryDetailSupport.ets');

function erase(source) {
  return source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace(/\bexport |\bprivate /g, '')
    .replace(/isCurrent: \(\) => boolean/g, 'isCurrent')
    .replace(/onDone\?: \(\) => void/g, 'onDone')
    .replace(/source\?: CoverSearchSource/g, 'source')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:common\.UIAbilityContext|CoverSearchSource|GalleryDetail|GallerySite|GalleryListLoadResult|DetailSearchRequest|SearchResultDraft|EhHttpClient|Error|string|number|boolean|void)\b/g, '');
}
function functionSource(source, name) {
  const start = source.search(new RegExp('(?:async )?function ' + name + '\\('));
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 2));
}
function methodSource(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 4));
}
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  return { promise, resolve, reject };
}
const ListMode = { ImageSearch: 4, Normal: 0 };
const GalleryCategory = { None: 0 };
const createSource = Function('EhUrl', functionSource(support, 'createCoverSearchSource') +
  '\nreturn createCoverSearchSource;')({
    getGalleryDetailUrl: (gid, token, _index, _all, site) =>
      `https://${site === 1 ? 'exhentai.org' : 'e-hentai.org'}/g/${gid}/${token}/`
  });
const createRequest = Function('ListMode', 'GalleryCategory',
  functionSource(detailSupport, 'createCoverSearchRequest') + '\nreturn createCoverSearchRequest;')(
  ListMode, GalleryCategory);
const open = Function('createCoverSearchSource', 'createCoverSearchRequest',
  'return {' + methodSource(host, 'openCoverSearch') + '}.openCoverSearch;')(createSource, createRequest);
const fixture = () => ({
  gid: 123, token: 'abc', thumb: 'https://thumb.example/123.jpg',
  previewSet: [{ index: 1, pageUrl: 'second-page' }, { index: 0, pageUrl: 'first-page' }]
});

test('cover search navigates synchronously without waiting for context, page loading or image caching', () => {
  const opened = [];
  const state = {
    detail: fixture(), detailLink: { site: 1 }, detailRequestUrl: '', renderVersion: 0,
    onOpenSearch: (request) => opened.push(request)
  };
  assert.equal(open.call(state), undefined);
  assert.equal(opened.length, 1, 'the click must present the search page before any promise settles');
  const request = opened[0];
  assert.equal(request.mode, ListMode.ImageSearch);
  assert.equal(request.imagePath, '');
  assert.equal(request.useSimilarityScan, true);
  assert.equal(request.onlySearchCovers, false);
  assert.equal(request.showExpunged, true);
  assert.equal(request.coverSearchSource.previewPageUrl, 'first-page');
  assert.equal(request.coverSearchSource.referer, 'https://exhentai.org/g/123/abc/');
  state.detail.gid = 456;
  state.detail.thumb = 'different-thumb';
  state.detail.previewSet[1].pageUrl = 'different-page';
  state.detailLink.site = 0;
  assert.equal(request.coverSearchSource.gid, 123, 'preparation must not read a later gallery from the host');
  assert.equal(request.coverSearchSource.thumb, 'https://thumb.example/123.jpg');
  assert.equal(request.coverSearchSource.previewPageUrl, 'first-page');
  assert.equal(request.coverSearchSource.site, 1);
  assert.doesNotMatch(methodSource(host, 'openCoverSearch'), /\.then\(|await |prepareCoverSearchImage/);
});

test('a gallery with neither a preview nor thumbnail reports an error instead of starting an empty upload', () => {
  let opened = 0;
  const state = { detail: { ...fixture(), previewSet: [], thumb: '' }, detailLink: { site: 0 },
    detailRequestUrl: '', renderVersion: 0, onOpenSearch() { opened++; } };
  open.call(state);
  assert.equal(opened, 0);
  assert.equal(state.detailStatus, 'Cover image is unavailable');
});

function preparer(cache) {
  return Function('readerImageCache', 'IMAGE_DOWNLOAD_PRIORITY_INTERACTIVE', 'readerPageImageCacheKey',
    functionSource(support, 'prepareCoverSearchImage') + '\nreturn prepareCoverSearchImage;')(
      cache, 100, () => 'full-image-cache-key');
}
const fullPage = { ok: true, page: { imageUrl: 'full-image', pageUrl: 'image-referer' } };
const source = createSource(fixture(), 1, 'detail-referer');

test('full-size cache hits keep original quality and avoid downloading the thumbnail', async () => {
  const pageCalls = [];
  const prepare = preparer({ getCachedPath: () => 'cached-full.jpg', ensureCached() { assert.fail('cache hit'); } });
  const path = await prepare({}, { async loadGalleryPageFast(...args) { pageCalls.push(args); return fullPage; } },
    source, () => true);
  assert.equal(path, 'cached-full.jpg');
  assert.deepEqual(pageCalls, [['first-page', 1, 'detail-referer']]);
});

test('uncached full-size cover retains interactive priority, referer, logical cache key and retry limit', async () => {
  const calls = [];
  const prepare = preparer({ getCachedPath: () => '', async ensureCached(...args) { calls.push(args); return 'full.jpg'; } });
  assert.equal(await prepare({}, { loadGalleryPageFast: async () => fullPage }, source, () => true), 'full.jpg');
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].slice(1), ['full-image', 'image-referer', 100, undefined, 'full-image-cache-key', { retryLimit: 3 }]);
});

test('full-size failures still fall back to the same thumbnail and cache key', async () => {
  const calls = [];
  const prepare = preparer({ getCachedPath: () => '', async ensureCached(...args) { calls.push(args); return 'thumb.jpg'; } });
  const path = await prepare({}, { async loadGalleryPageFast() { throw new Error('page unavailable'); } }, source, () => true);
  assert.equal(path, 'thumb.jpg');
  assert.deepEqual(calls[0].slice(1), ['https://thumb.example/123.jpg', 'detail-referer', 100, undefined, 'cover-search-123']);
});

test('returning while the image page loads stops the download and thumbnail fallback', async () => {
  const pending = deferred();
  let active = true;
  const prepare = preparer({ getCachedPath() { assert.fail('cancelled'); }, ensureCached() { assert.fail('cancelled'); } });
  const request = prepare({}, { loadGalleryPageFast: () => pending.promise }, source, () => active);
  active = false;
  pending.resolve(fullPage);
  assert.equal(await request, '');
  assert.equal(await prepare({}, { loadGalleryPageFast() { assert.fail('already cancelled'); } }, source, () => false), '');
});

function scene(prepareImage, context = {}) {
  const methods = Function('prepareCoverSearchImage', 'getAbilityContext', 'ListMode', 'return {' +
    ['loadRemote', 'loadCoverSearchPage', 'aboutToDisappear'].map((name) => methodSource(gallery, name)).join(',\n') +
    '};')(prepareImage, () => context, ListMode);
  return Object.assign(methods, {
    coverSearchSource: source, searchMode: ListMode.ImageSearch, imageSearchPath: '',
    listRequestGate: { value: 0, begin() { return ++this.value; }, isCurrent(value) { return value === this.value; } },
    uploads: [], applied: [], failures: [], statusText: '',
    beginListReplacement() { this.statusText = 'Loading...'; return this.listRequestGate.begin(); },
    async loadRoutePageWithFallback(page) { this.uploads.push([page, this.imageSearchPath]); return { ok: true }; },
    applyListReplacementResult(generation, result) { if (this.listRequestGate.isCurrent(generation)) this.applied.push(result); },
    applyListReplacementFailure(generation, error) {
      if (this.listRequestGate.isCurrent(generation)) { this.statusText = 'Load failed: ' + error.message; this.failures.push(error); }
    },
    unregisterActiveBackHandler() {}, saveListCache() {}, saveNavigationCache() {}
  });
}
const settle = () => new Promise((resolve) => setImmediate(resolve));

test('search scene shows loading while preparing, then searches with the prepared path exactly once', async () => {
  const pending = deferred();
  const state = scene(() => pending.promise);
  state.loadRemote(0);
  assert.equal(state.statusText, 'Loading...');
  assert.deepEqual(state.uploads, []);
  pending.resolve('prepared.jpg');
  await settle();
  assert.deepEqual(state.uploads, [[0, 'prepared.jpg']]);
  assert.deepEqual(state.applied, [{ ok: true }]);
  state.loadRemote(0); // Refresh reuses the prepared file rather than fetching the cover again.
  await settle();
  assert.equal(state.uploads.length, 2);
});

test('returning or replacing a search during image download cannot upload or overwrite the newer request', async () => {
  for (const cancel of [(state) => state.aboutToDisappear(), (state) => state.listRequestGate.begin()]) {
    const pending = deferred();
    const state = scene(() => pending.promise);
    state.loadRemote(0);
    cancel(state);
    state.imageSearchPath = 'newer-selection.jpg';
    pending.resolve('old-cover.jpg');
    await settle();
    assert.deepEqual(state.uploads, []);
    assert.deepEqual(state.applied, []);
    assert.deepEqual(state.failures, []);
    assert.equal(state.imageSearchPath, 'newer-selection.jpg');
  }
});

test('empty, rejected or context-unavailable preparation reports failure in the search scene without uploading', async () => {
  for (const [prepare, context, message] of [
    [async () => '', {}, 'Cover image cache failed'],
    [async () => { throw new Error('network timeout'); }, {}, 'network timeout'],
    [async () => 'unused.jpg', null, 'Cover image is unavailable']
  ]) {
    const state = scene(prepare, context === null ? undefined : context);
    // Explicitly undefined is otherwise replaced by scene()'s default context.
    if (context === null) {
      state.loadCoverSearchPage = Function('getAbilityContext', 'prepareCoverSearchImage', 'return {' +
        methodSource(gallery, 'loadCoverSearchPage') + '}.loadCoverSearchPage;')(() => undefined, prepare);
    }
    state.loadRemote(0);
    await settle();
    assert.deepEqual(state.uploads, []);
    assert.equal(state.statusText, 'Load failed: ' + message);
  }
});

test('ordinary searches and selected image files keep their existing direct request path', async () => {
  for (const [mode, imagePath] of [[ListMode.Normal, ''], [ListMode.ImageSearch, 'picked.jpg']]) {
    const state = scene(() => assert.fail('should not prepare a cover'));
    state.searchMode = mode;
    state.imageSearchPath = imagePath;
    state.loadRemote(0);
    await settle();
    assert.deepEqual(state.uploads, [[0, imagePath]]);
    assert.equal(state.applied.length, 1);
  }
});

test('nested gallery, download and toplist routes retain the cover request across navigation', () => {
  const listSupport = read('components/GalleryListSupport.ets');
  const clone = Function(functionSource(listSupport, 'cloneSearchResultDraft') + '\nreturn cloneSearchResultDraft;')();
  assert.deepEqual(clone({ coverSearchSource: source }).coverSearchSource, source);
  assert.match(gallery, /coverSearchSource: request.coverSearchSource/);
  assert.match(gallery, /initialCoverSearchSource: this.searchResultDraft.coverSearchSource/);
  assert.match(gallery, /this.coverSearchSource = this.initialCoverSearchSource/);
  for (const file of ['DownloadScene.ets', 'TopListScene.ets']) {
    const route = read('components/' + file);
    assert.match(route, /this.tagSearchCoverSource = request.coverSearchSource/);
    assert.match(route, /initialCoverSearchSource: this.tagSearchCoverSource/);
    assert.match(route, /tagSearchCoverSource: this.tagSearchCoverSource/);
    assert.match(route, /this.tagSearchCoverSource = cache.tagSearchCoverSource/);
  }
});

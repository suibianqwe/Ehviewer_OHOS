import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');

// Run the production lifecycle methods, replacing only platform dependencies.
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return source.slice(start, end + 4).replace(/\bprivate /g, '')
    .replace(/event\?: ReaderImageCompleteEvent/g, 'event')
    .replace(/: Promise<void>/g, '')
    .replace(/: (?:ReaderCropRect|ReaderPageGroupItem|number|string|boolean|void)\b(?:\[\])?/g, '');
}

class CropRect {
  constructor(x = 0, y = 0, width = 1, height = 1) { Object.assign(this, { x, y, width, height }); }
}

function viewport(source) {
  const scheduled = [], sizeCache = [], completeCache = [], cropRequests = [];
  const names = ['onImageComplete', 'onImageError', 'loadCropRect', 'retryImage',
    'releaseRuntimeState', 'onImageAdjustmentChange', 'onCropWhiteBordersChange', 'onSuperResolutionTargetChange'];
  const model = Function('setTimeout', 'cacheReaderSourceImageSize', 'cacheReaderImageComplete',
    'readerWhiteBorderCropService', 'ReaderCropRect', 'forgetReaderImageRuntimeState',
    'return {' + names.map((name) => method(source, name)).join(',\n') + '};')(
    (callback) => scheduled.push(callback), (...args) => sizeCache.push(args), (url) => completeCache.push(url),
    { analyze(key, path) {
      return new Promise((resolve, reject) => { cropRequests.push({ key, path, resolve, reject }); });
    } }, CropRect, () => {});
  return Object.assign(model, {
    url: 'file://page-a.jpg', pixelMap: undefined, path: '/page-a.jpg',
    sourceSizeRequestId: 1, imageRetryVersion: 0, downloadProgressRequestId: 0,
    sourceImageWidth: 0, sourceImageHeight: 0, completedImageUrl: '', failedImageUrl: '',
    cropWhiteBorders: false, cropRequestId: 0, retainedCropKey: '', cropRect: new CropRect(),
    retainedAdjustmentSettingsKey: 'unchanged', imageAdjustmentSettings: { cacheKey: () => 'unchanged' },
    animationPlayback: { reset() {} },
    layoutUpdates: 0, sizeReports: 0, retries: 0, processingCalls: [],
    imageUrl() { return this.url; }, displayImageSource() { return this.pixelMap ?? this.url; },
    displayPixelMap() { return this.pixelMap; }, localSourceImagePath() { return this.path; },
    sourceImageCacheKey() { return 'gallery/page'; },
    updateDisplayImageSize() { this.layoutUpdates++; }, reportImageSize() { this.sizeReports++; },
    loadAdjustedPixelMap() { this.processingCalls.push('adjust'); },
    loadSuperResolutionPixelMap() { this.processingCalls.push('sr'); },
    loadHdrPixelMap() { this.processingCalls.push('hdr'); },
    releaseAdjustedPixelMap() { this.processingCalls.push('release-adjust'); },
    releaseSuperResolutionPixelMap() { this.processingCalls.push('release-sr'); },
    releaseHdrPixelMap() { this.processingCalls.push('release-hdr'); },
    onRetry() { this.retries++; }, startDownloadProgressMonitor() {},
    onImageReady() {},
    onImageFailed() {},
    flush() { while (scheduled.length > 0) scheduled.shift()(); },
    sizeCache, completeCache, cropRequests
  });
}

const loaded = (loadingStatus = 1, width = 1000, height = 1500) => ({ loadingStatus, width, height });

for (const name of ['ReaderImageViewport', 'ReaderContinuousImageItem']) {
  const source = read('components/reader/viewports/' + name + '.ets');

  test(name + ': resize reuses adjusted images and only rebuilds size-dependent enhancement', () => {
    const state = viewport(source);
    state.superResolutionEnabled = false;
    state.onSuperResolutionTargetChange();
    assert.deepEqual(state.processingCalls, []);
    state.superResolutionEnabled = true;
    state.onSuperResolutionTargetChange();
    assert.deepEqual(state.processingCalls, ['release-hdr', 'release-sr', 'sr', 'hdr']);
  });

  test(name + ': cached callbacks defer state updates; metadata is not a decoded frame', () => {
    const state = viewport(source);
    state.onImageComplete(loaded(0));
    assert.equal(state.sourceImageWidth, 0);
    assert.equal(state.completedImageUrl, '');
    state.flush();
    assert.deepEqual(state.sizeCache, [[state.url, 1000, 1500]]);
    assert.equal(state.completedImageUrl, '');
    state.onImageComplete(loaded());
    assert.equal(state.completedImageUrl, '');
    state.flush();
    assert.equal(state.completedImageUrl, state.url);
    assert.equal(state.layoutUpdates, 1);
    assert.deepEqual(state.completeCache, [state.url]);
    assert.deepEqual(state.processingCalls, []);
  });

  test(name + ': repeated decode/resize callbacks cannot restart processing or relayout', () => {
    const state = viewport(source);
    state.onImageComplete(loaded());
    state.flush();
    for (let i = 0; i < 50; i++) {
      state.onImageComplete(loaded(i % 2));
      state.flush();
    }
    assert.equal(state.layoutUpdates, 1);
    assert.equal(state.sizeReports, 1);
    assert.equal(state.completeCache.length, 1);
    assert.deepEqual(state.processingCalls, []);
    assert.equal(state.cropRequests.length, 0);
  });

  test(name + ': retry, exit, source and PixelMap changes invalidate queued callbacks', () => {
    for (const change of [
      (state) => { state.retryImage(); },
      (state) => { state.releaseRuntimeState(); },
      (state) => { state.url = 'file://page-b.jpg'; state.sourceSizeRequestId++; },
      (state) => { state.pixelMap = {}; }
    ]) {
      const state = viewport(source);
      state.onImageComplete(loaded());
      state.onImageError();
      change(state);
      state.flush();
      assert.equal(state.completedImageUrl, '');
      assert.equal(state.failedImageUrl, '');
      assert.equal(state.sourceImageWidth, 0);
    }
  });

  test(name + ': errors remain retryable; enhanced dimensions never replace original dimensions', () => {
    const state = viewport(source);
    state.onImageError();
    assert.equal(state.failedImageUrl, '');
    state.flush();
    assert.equal(state.failedImageUrl, state.url);
    state.retryImage();
    state.pixelMap = {};
    state.onImageComplete(loaded(1, 2000, 3000));
    state.flush();
    assert.equal(state.completedImageUrl, state.url);
    assert.equal(state.failedImageUrl, '');
    assert.equal(state.sourceImageWidth, 0);
    assert.equal(state.retries, 1);
  });

  test(name + ': unchanged settings preserve processed images; real changes still reload all stages', () => {
    const state = viewport(source);
    state.onImageAdjustmentChange();
    assert.deepEqual(state.processingCalls, []);
    state.imageAdjustmentSettings = { cacheKey: () => 'different' };
    state.onImageAdjustmentChange();
    assert.deepEqual(state.processingCalls, ['release-hdr', 'release-sr', 'release-adjust', 'adjust', 'sr', 'hdr']);
    state.processingCalls = [];
    state.onImageAdjustmentChange();
    assert.deepEqual(state.processingCalls, []);
  });

  test(name + ': crop analysis runs once per source and unchanged rectangles do not relayout', async () => {
    const state = viewport(source);
    state.loadCropRect();
    assert.equal(state.layoutUpdates, 0);
    state.cropWhiteBorders = true;
    state.loadCropRect();
    state.loadCropRect();
    assert.equal(state.cropRequests.length, 1);
    state.cropRequests[0].resolve(new CropRect());
    await Promise.resolve();
    assert.equal(state.layoutUpdates, 0);
    state.loadCropRect();
    assert.equal(state.cropRequests.length, 1);
    state.path = '/page-b.jpg';
    state.loadCropRect();
    state.cropRequests[1].resolve(new CropRect(0.1, 0.1, 0.8, 0.8));
    await Promise.resolve();
    assert.equal(state.layoutUpdates, 1);
    assert.equal(state.sizeReports, 1);
    state.loadCropRect();
    assert.equal(state.cropRequests.length, 2);
  });

  test(name + ': turning crop off discards pending results; re-enabling analyzes again', async () => {
    const state = viewport(source);
    state.cropWhiteBorders = true;
    state.loadCropRect();
    state.cropWhiteBorders = false;
    state.onCropWhiteBordersChange();
    state.cropRequests[0].resolve(new CropRect(0.1, 0.1, 0.8, 0.8));
    await Promise.resolve();
    assert.deepEqual(state.cropRect, new CropRect());
    state.cropWhiteBorders = true;
    state.onCropWhiteBordersChange();
    assert.equal(state.cropRequests.length, 2);
  });
}

const sceneSource = read('components/ReaderScenes.ets');
function scene() {
  const model = Function('return {' + method(sceneSource, 'syncReaderPageIndexSource') + '};')();
  return Object.assign(model, {
    galleryId: 123, totalPages: 6, readerPageIndexesCount: -1, readerPageIndexesReversed: false,
    readerPageIndexesSignature: '', swiperReversed: false, currentIndex: 0,
    groups: [0, 1, 2, 3, 4, 5], pairs: new Set(), mountedPairedPageKeys: [],
    pageIndexes() { this.readerGroupingSignature = this.groups.join(','); return this.groups; },
    shouldPairPage(index) { return this.pairs.has(index); }, pageGroupAnchorForPageIndex(index) { return index; },
    scheduleSwiperSourceSync() {},
    readerPageIndexesSource: { items: [], setItems(items) { this.items = items; } }
  });
}

test('background page grouping retains current image nodes and mounted paired gestures', () => {
  const state = scene();
  state.groups = [0, 2, 3, 4, 5];
  state.pairs.add(0);
  state.syncReaderPageIndexSource();
  const before = state.readerPageIndexesSource.items;
  state.mountedPairedPageKeys = [before[0].key];
  state.groups = [0, 2, 3, 4]; // Only the last group becomes paired as its image finishes loading.
  state.pairs.add(4);
  state.syncReaderPageIndexSource();
  const after = state.readerPageIndexesSource.items;
  for (const index of [0, 2, 3]) {
    assert.equal(after.find((item) => item.index === index).key, before.find((item) => item.index === index).key);
  }
  assert.equal(after[3].key, before[3].key, 'single -> paired retains the physical first page node');
  assert.deepEqual(state.mountedPairedPageKeys, [before[0].key]);
});

test('direction changes preserve page identity, while changing galleries replaces it', () => {
  const state = scene();
  state.syncReaderPageIndexSource();
  const before = state.readerPageIndexesSource.items;
  state.swiperReversed = true;
  state.groups.reverse();
  state.syncReaderPageIndexSource();
  assert.deepEqual(state.readerPageIndexesSource.items.map((item) => item.key), before.map((item) => item.key).reverse());
  state.galleryId = 456;
  state.readerPageIndexesCount = -1; // onGalleryIdChange invalidates the source.
  state.syncReaderPageIndexSource();
  assert.ok(state.readerPageIndexesSource.items.every((item) => !before.some((old) => old.key === item.key)));
});

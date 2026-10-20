import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const item = read('components/reader/viewports/ReaderContinuousImageItem.ets');
const scene = read('components/ReaderScenes.ets');
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace(/\bprivate /g, '')
    .replace(/: (?:number|string|boolean|void)\b(?:\[\])?/g, '');
}

test('continuous scroll positions and item height changes do not recalculate zoom geometry', () => {
  const resize = Function('return {' + method(item, 'onItemWidthChange') + '}.onItemWidthChange;')();
  const state = { componentWidth: 1, layouts: 0, updateDisplayImageSize() { this.layouts++; } };
  resize.call(state, 940);
  for (let i = 0; i < 240; i++) resize.call(state, 940 + i % 2 * 0.001);
  assert.equal(state.layouts, 1);
  for (const invalid of [0, -1, Number.NaN]) resize.call(state, invalid);
  assert.equal(state.layouts, 1);
  resize.call(state, 460);
  assert.equal(state.componentWidth, 460);
  assert.equal(state.layouts, 2, 'folding/rotation still applies the actual new width');
  assert.match(item, /onAreaChange[\s\S]*?this\.onItemWidthChange\(width\)/);
});

test('rendering a resolved continuous image performs no filesystem checks', async () => {
  let diskChecks = 0, resets = 0;
  const code = ['imageUrl', 'imageSourceIdentity'].map(name => method(item, name)).join(',\n');
  const state = Function('return {' + code + '};')();
  Object.assign(state, {
    page: { cachedImagePath: 'file://page-a.webp' }, preferOriginal: false,
    resolvedImageUrl: '', retainedImageUrl: '', retainedSourceIdentity: '', sourceSizeRequestId: 0,
    imageAdjustmentSettings: { cacheKey: () => '' }, animationPlayback: { reset() { resets++; } },
    sourceImageCacheKey: () => 'page', releaseHdrPixelMap() {}, releaseSuperResolutionPixelMap() {},
    releaseAdjustedPixelMap() {}, updateDisplayImageSize() {}, loadCachedSourceImageSize: async () => {},
    loadAdjustedPixelMap() {}, loadSuperResolutionPixelMap() {}, loadHdrPixelMap() {}, loadCropRect() {},
    startDownloadProgressMonitor() {}
  });
  // onImageSourceChange also creates the existing crop model.
  const Crop = class {};
  const change = Function('ReaderCropRect', 'readerDisplayImageUrl', 'cachedReaderSourceImageSize',
    'isReaderImageComplete', 'forgetReaderImageRuntimeState',
    'return {' + method(item, 'onImageSourceChange') + '}.onImageSourceChange;')(
    Crop, page => { diskChecks++; return page.cachedImagePath; }, () => ({ width: 832, height: 832 }), () => false, () => {});
  state.onImageSourceChange = change;
  state.onImageSourceChange();
  for (let i = 0; i < 240; i++) assert.equal(state.imageUrl(), 'file://page-a.webp');
  assert.equal(diskChecks, 1);
  state.onImageSourceChange();
  assert.equal(diskChecks, 2, 'prop updates still revalidate files');
  assert.equal(resets, 1, 'unchanged source does not restart its native animation');
  state.page.cachedImagePath = 'file://page-b.webp';
  state.onImageSourceChange();
  assert.equal(state.imageUrl(), 'file://page-b.webp');
  assert.equal(resets, 2);
  state.page.cachedImagePath = '';
  state.onImageSourceChange();
  assert.equal(state.imageUrl(), '', 'invalidated files cannot keep a stale render source');
  assert.equal(resets, 3);
  await Promise.resolve();
});

test('continuous visible range reports additions and removals once, without losing secondary visible pages', () => {
  const scroll = Function('return {' + method(scene, 'onContinuousScrollIndex') + '}.onContinuousScrollIndex;')();
  const visible = [], jumps = [];
  const state = {
    currentIndex: 0, continuousScrollTarget: -1, continuousScrollTimer: -1, continuousVisiblePageIndexes: [],
    pageIndexForVisualIndex: index => index, onVisiblePageIndexesChange: pages => visible.push(pages),
    scheduleImageProcessingPrefetch() {}, onJump: index => jumps.push(index)
  };
  for (let i = 0; i < 240; i++) scroll.call(state, 0, 1);
  assert.deepEqual(visible, [[0, 1]]);
  scroll.call(state, 0, 2);
  assert.deepEqual(visible.at(-1), [0, 1, 2]);
  scroll.call(state, 1, 2);
  assert.deepEqual(visible.at(-1), [1, 2]);
  assert.deepEqual(jumps, [1]);
  state.continuousScrollTarget = 10;
  scroll.call(state, 2, 3);
  assert.equal(visible.length, 3, 'ignore intermediate indexes during an explicit jump');
  scroll.call(state, 10, 11);
  assert.deepEqual(visible.at(-1), [10, 11]);
  assert.deepEqual(jumps, [1, 10]);
});

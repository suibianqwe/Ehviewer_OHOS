import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/components/DownloadScene.ets', import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');

// Execute the production methods, erasing only their ArkTS annotations (Node 20+).
function method(name) {
  const start = source.search(new RegExp('^  (?:private )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return source.slice(start, end + 4).replace(/\bprivate /g, '')
    .replace(/observedOffset\?: number/g, 'observedOffset')
    .replace(/: (?:OffsetResult|number|void)(?: \| undefined)?/g, '');
}
const normalizeStart = source.indexOf('function normalizeSceneScrollOffset(');
const normalizeSource = source.slice(normalizeStart, source.indexOf('\n}', normalizeStart) + 2)
  .replace(/: number/g, '');
const normalize = Function(normalizeSource + '; return normalizeSceneScrollOffset;')();

function createModel() {
  const updates = [];
  const cleanup = [];
  const store = {
    updateDownloadPosition(anchorId, anchorIndex, offset) { updates.push({ anchorId, anchorIndex, offset }); },
    flush() { cleanup.push('flush'); }
  };
  const methods = Function('normalizeSceneScrollOffset', 'ehBrowsePositionStore', 'markGalleryListScrolling',
    'nextFloatingToolbarOffset', 'return {' + [
      'readDownloadScrollOffset', 'rememberDownloadScrollOffset', 'handleDownloadListDidScroll',
      'updateToolbarForScrollFrame', 'aboutToDisappear'
    ].map(method).join(',\n') + '};')(normalize, store, () => {}, (old, delta, _offset, height) =>
      Math.max(-height, Math.min(0, old - delta)));
  const model = Object.assign(methods, {
    updates, cleanup, current: { xOffset: 0, yOffset: 420 }, offsetReads: 0,
    visibleItems: [{ gid: 10 }, { gid: 20 }, { gid: 30 }], downloadFirstVisibleIndex: 1,
    downloadScrollOffset: 200, downloadBrowsePositionLoaded: true, restoringDownloadBrowsePosition: false,
    toolbarOffsetY: -60, lastToolbarScrollOffset: 200, toolbarRestoring: false,
    syncToolbarOffsetState() {}, floatingToolbarHeight() { return 88; },
    toolbarVisibleHeight() { return Math.max(0, 88 + this.toolbarOffsetY); },
    restoreToolbarOnReverseScroll() { this.toolbarOffsetY = 0; },
    cardScrollAnchor: { clear() { cleanup.push('anchor'); } },
    saveNavigationCache() { cleanup.push('navigation'); },
    stopDownloadListWork() {},
    unsubscribeStore() { cleanup.push('store'); },
    unsubscribeDownloadManager() { cleanup.push('manager'); },
    floatingActionSideController: { dispose() { cleanup.push('floating'); } }
  });
  model.downloadScroller = { currentOffset() { model.offsetReads++; return model.current; } };
  return model;
}

test('download exit after the scroller detaches preserves the last valid position and finishes cleanup', () => {
  const state = createModel();
  state.handleDownloadListDidScroll();
  assert.deepEqual(state.updates, [{ anchorId: '20', anchorIndex: 1, offset: 420 }]);
  state.current = undefined; // Same state as the 2026-10-11 16:46:48 real-device JS crash.
  state.downloadFirstVisibleIndex = 0; // Visibility callbacks may run while child nodes are being removed.
  assert.doesNotThrow(() => state.aboutToDisappear());
  assert.equal(state.downloadScrollOffset, 420);
  assert.deepEqual(state.updates, [{ anchorId: '20', anchorIndex: 1, offset: 420 }]);
  assert.deepEqual(state.cleanup, ['flush', 'anchor', 'navigation', 'store', 'manager', 'floating']);
});

test('undefined, null, invalid offsets and a disposed controller do not reset saved state', () => {
  for (const value of [undefined, null, {}, { yOffset: undefined }, { yOffset: NaN },
    { yOffset: Infinity }, { yOffset: -Infinity }, { yOffset: '0' }]) {
    const state = createModel();
    state.current = value;
    assert.equal(state.readDownloadScrollOffset(), undefined);
    state.rememberDownloadScrollOffset();
    assert.equal(state.downloadScrollOffset, 200);
    assert.deepEqual(state.updates, []);
  }
  const disposed = createModel();
  disposed.downloadScroller.currentOffset = () => { throw new Error('controller disposed'); };
  assert.doesNotThrow(() => disposed.aboutToDisappear());
  assert.equal(disposed.downloadScrollOffset, 200);
  assert.deepEqual(disposed.updates, []);
  assert.ok(disposed.cleanup.includes('store'));
});

test('late scroll callbacks preserve toolbar state and the complete frame delta', () => {
  const state = createModel();
  state.current = undefined;
  for (const delta of [25, -25, 0]) {
    assert.equal(state.updateToolbarForScrollFrame(delta), delta);
    assert.doesNotThrow(() => state.handleDownloadListDidScroll());
    assert.doesNotThrow(() => state.rememberDownloadScrollOffset());
  }
  assert.equal(state.toolbarOffsetY, -60);
  assert.equal(state.lastToolbarScrollOffset, 200);
  assert.equal(state.downloadScrollOffset, 200);
  assert.deepEqual(state.updates, []);
});

test('a valid onDidScroll samples the controller once and persists the same offset', () => {
  const state = createModel();
  state.handleDownloadListDidScroll();
  assert.equal(state.offsetReads, 1, 'do not query the native controller twice in a scroll callback');
  assert.equal(state.downloadScrollOffset, 420);
  assert.equal(state.lastToolbarScrollOffset, 420);
  assert.equal(state.toolbarOffsetY, -88);
  assert.deepEqual(state.updates.at(-1), { anchorId: '20', anchorIndex: 1, offset: 420 });
});

test('a real return to the top or spring overscroll still records zero', () => {
  for (const yOffset of [0, 1, -20]) {
    const state = createModel();
    state.current = { yOffset };
    state.handleDownloadListDidScroll();
    assert.equal(state.downloadScrollOffset, 0);
    assert.equal(state.toolbarOffsetY, 0);
    assert.equal(state.updates.at(-1).offset, 0);
  }
});

test('in-flight browse restoration and unloaded preferences are not overwritten', () => {
  const restoring = createModel();
  restoring.restoringDownloadBrowsePosition = true;
  restoring.aboutToDisappear();
  assert.equal(restoring.downloadScrollOffset, 200);
  assert.deepEqual(restoring.updates, []);
  assert.equal(restoring.offsetReads, 0);
  const unloaded = createModel();
  unloaded.downloadBrowsePositionLoaded = false;
  unloaded.rememberDownloadScrollOffset();
  assert.equal(unloaded.downloadScrollOffset, 420);
  assert.deepEqual(unloaded.updates, []);
});

test('a genuinely empty loaded download list keeps the existing empty-position behavior', () => {
  const state = createModel();
  state.visibleItems = [];
  state.current = undefined;
  state.aboutToDisappear();
  assert.equal(state.downloadScrollOffset, 0);
  assert.deepEqual(state.updates, [{ anchorId: '', anchorIndex: 0, offset: 0 }]);
});

test('List and WaterFlow use the guarded callbacks; no direct offset dereference remains', () => {
  for (const name of ['downloadStandardList', 'downloadThumbnailWaterFlow']) {
    const start = source.indexOf('  private ' + name + '(');
    const end = source.indexOf('\n  }', start);
    const builder = source.slice(start, end);
    assert.match(builder, /onDidScroll[\s\S]*this\.handleDownloadListDidScroll\(\)/);
    assert.match(builder, /onScrollStop[\s\S]*this\.rememberDownloadScrollOffset\(\)/);
  }
  assert.doesNotMatch(source, /currentOffset\(\)\.[xy]Offset/);
  assert.equal((source.match(/currentOffset\(\)/g) || []).length, 2); // One documentation comment + one guarded call.
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const download = read('components/DownloadScene.ets');
const gallery = read('components/GalleryScenes.ets');
const navigation = read('components/NavigationComponents.ets');
const layout = read('shared/AdaptiveGalleryListLayout.ets');
const shared = read('shared/EhShared.ets');

function body(source, signature) {
  const method = source.indexOf(signature);
  assert.ok(method >= 0, signature);
  const start = source.indexOf('{', method);
  let depth = 1;
  let end = start + 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(start + 1, end - 1);
}

const visibleHeight = Function('offsetY', 'expandedHeight', body(shared, 'function immersiveChromeHeightFromOffset('));
const offsetFromHeight = Function('height', 'expandedHeight', body(shared, 'function immersiveChromeOffsetFromHeight('));
const nextHeight = Function('currentHeight', 'scrollOffset', 'contentOffset', 'expandedHeight',
  body(shared, 'function nextImmersiveChromeHeight('));
const nextOffset = Function('immersiveChromeHeightFromOffset', 'nextImmersiveChromeHeight',
  'immersiveChromeOffsetFromHeight', 'currentOffset', 'scrollOffset', 'contentOffset', 'barHeight',
  body(shared, 'function nextFloatingToolbarOffset(')).bind(null, visibleHeight, nextHeight, offsetFromHeight);
const downloadFrame = Function('normalizeSceneScrollOffset', 'nextFloatingToolbarOffset', 'scrollOffset',
  body(download, 'private updateToolbarForScrollFrame(')).bind(null, (value) => Math.max(0, value), nextOffset);
const galleryFrame = Function('normalizeGalleryListScrollOffset', 'nextFloatingToolbarOffset', 'scrollOffset',
  body(gallery, 'private handleScrollFrame('));
// Bind dependencies without binding `this`, so the real page methods run against the same model state.
const downloadFrameWithState = Function('normalizeSceneScrollOffset', 'nextFloatingToolbarOffset', 'scrollOffset',
  body(download, 'private updateToolbarForScrollFrame('));

function state(height) {
  const model = {
    toolbarOffsetY: 0, toolbarRestoring: false, contentOffset: 100, restores: 0,
    floatingToolbarHeight() { return height; }, totalBarHeight() { return height; },
    toolbarVisibleHeight() { return visibleHeight(this.toolbarOffsetY, height); },
    visibleBarHeight() { return visibleHeight(this.toolbarOffsetY, height); },
    restoreToolbarOnReverseScroll() { this.restores++; this.toolbarOffsetY = 0; }
  };
  model.downloadScroller = model.listScroller = { currentOffset: () => ({ yOffset: model.contentOffset }) };
  return model;
}

test('downloads preserve the entire scroll delta while hiding and restoring the toolbar like home', () => {
  for (const height of [64, 88, 104, 128]) {
    const actual = state(height);
    const expected = state(height);
    for (const delta of [8, 20, 150, 25, -12, -80, 10, 120, -5]) {
      const remaining = downloadFrameWithState.call(actual, (n) => Math.max(0, n), nextOffset, delta);
      const homeRemaining = galleryFrame.call(expected, (n) => Math.max(0, n), nextOffset, delta);
      assert.equal(remaining, delta, 'toolbar animation must not consume list movement');
      assert.equal(remaining, homeRemaining);
      assert.equal(actual.toolbarOffsetY, expected.toolbarOffsetY);
      assert.equal(actual.restores, expected.restores);
      actual.contentOffset += remaining;
      expected.contentOffset += homeRemaining;
    }
    actual.contentOffset = 0;
    actual.toolbarOffsetY = -height;
    downloadFrameWithState.call(actual, (n) => Math.max(0, n), nextOffset, -5);
    assert.equal(actual.toolbarOffsetY, 0, 'returning to the top restores the title');
  }
});

test('both pages use fixed content spacing for every toolbar visibility and screen size', () => {
  const inset = Function('uiTitleBarFadeHeight', 'toolbarHeight', body(layout, 'function galleryListTopInset('));
  const downloadInset = Function('galleryListTopInset', body(download, 'private downloadContentStartOffset('));
  const homeInset = Function('galleryListTopInset', body(gallery, 'private expandedTitleContentInset('));
  for (const fade of [8, 36]) {
    for (const height of [64, 88, 104, 128]) {
      const model = state(height);
      for (const offset of [0, -height / 2, -height]) {
        model.toolbarOffsetY = offset;
        const fixedInset = (h) => inset(() => fade, h);
        assert.equal(downloadInset.call(model, fixedInset), height + fade * 0.68);
        assert.equal(downloadInset.call(model, fixedInset), homeInset.call(model, fixedInset));
      }
    }
  }
});

test('download spacing scrolls away with list content and never pads the WaterFlow viewport', () => {
  const placeholder = body(download, 'private downloadListTopPlaceholder(');
  assert.match(placeholder, /height\(this\.downloadContentStartOffset\(\)\)/);
  assert.doesNotMatch(placeholder, /backgroundColor|downloadListEdgeSpacer/);
  const list = body(download, 'private downloadStandardList(');
  assert.match(list, /header: this\.downloadListTopPlaceholder\(\)/);
  const flow = body(download, 'private downloadThumbnailWaterFlow(');
  assert.match(flow, /\.margin\(\{ top: index < this\.downloadColumnCount\(\) \? this\.downloadContentStartOffset\(\) : 0 \}\)/);
  assert.doesNotMatch(flow, /\.padding\(\{[^}]*top:/);
  for (const source of [list, flow]) {
    assert.match(source, /\.height\('100%'\)/);
    assert.match(source, /\.scrollBar\(BarState\.Auto\)/);
  }
});

test('rendered toolbar uses the pane height supplied by the download scroll controller', () => {
  const height = Function('uiAdaptiveToolbarHeight', body(navigation, 'private barBodyHeight('));
  assert.equal(height.call({ toolbarHeight: 56, contentWidth: 1000 }, () => 72), 56);
  assert.equal(height.call({ toolbarHeight: 0, contentWidth: 1000 }, () => 72), 72);
  assert.match(body(navigation, 'private navigationBar('), /toolbarHeight: this\.toolbarHeight/);
  assert.match(body(navigation, 'private totalToolbarHeight('), /this\.statusBarVp\(\) \+ this\.toolbarHeight/);
});

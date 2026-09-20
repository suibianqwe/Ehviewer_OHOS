import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const download = read('components/DownloadScene.ets');
const split = read('components/SplitPaneSupport.ets');

function block(source, signature) {
  const index = source.indexOf(signature);
  assert.ok(index >= 0, signature);
  const start = signature.endsWith('{') ? index + signature.length - 1 : source.indexOf('{', index);
  let depth = 1;
  let end = start + 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return { body: source.slice(start + 1, end - 1), tail: source.slice(end) };
}

const build = block(download, '  build()').body;
const root = block(build, 'Stack({ alignContent: Alignment.TopStart }) {');
const widthExpression = root.tail.match(/\.width\(([^\r\n]+)\)/)[1];
const rootWidth = Function('return ' + widthExpression);
const constant = (name) => Number(split.match(new RegExp('const ' + name + ': number = ([\\d.]+)'))[1]);
const breakpoint = constant('SPLIT_PANE_BREAKPOINT');
const clampRatio = Function('SPLIT_PANE_MIN_RATIO', 'SPLIT_PANE_MAX_RATIO', 'value',
  block(split, 'function clampSplitPaneRatio(').body)
  .bind(null, constant('SPLIT_PANE_MIN_RATIO'), constant('SPLIT_PANE_MAX_RATIO'));
const listWidth = Function('clampSplitPaneRatio', 'totalWidth', 'ratio', 'minList', 'minSide',
  block(split, 'function splitPaneListWidth(').body).bind(null, clampRatio);
const sideWidth = Function('totalWidth', 'listWidth', 'minSide', block(split, 'function splitPaneSideWidth(').body);

function model(windowWidth, splitEnabled = true) {
  const state = {
    windowWidth, sceneContentWidth: 0, downloadContentWidth: 0, splitListRatio: 0.42,
    showDetail: false, downloadLabelManagerVisible: false, showTagSearch: false,
    rememberedWidths: [], rightPaneStates: [],
    windowContentWidthVp() { return this.windowWidth; }
  };
  const deps = {
    splitPaneModeEnabled: () => splitEnabled,
    SPLIT_PANE_BREAKPOINT: breakpoint,
    splitPaneListWidth: (width, ratio) => listWidth(width, ratio,
      constant('SPLIT_PANE_LIST_MIN_WIDTH'), constant('SPLIT_PANE_SIDE_MIN_WIDTH')),
    splitPaneSideWidth: (width, left) => sideWidth(width, left, constant('SPLIT_PANE_SIDE_MIN_WIDTH')),
    rememberMainContentWidthVp: (width) => state.rememberedWidths.push(width),
    markCurrentRouteRightPane: (visible) => state.rightPaneStates.push(visible)
  };
  for (const [name, args] of [
    ['availableSceneWidth', []], ['useSplitLayout', []], ['splitListPaneWidth', []],
    ['splitSidePaneWidth', []], ['syncDownloadContentWidthForCurrentLayout', []],
    ['updateDownloadContentWidth', ['width']], ['updateDownloadContentWidthFromArea', ['width']],
    ['updateSceneContentWidth', ['width']]
  ]) {
    const method = Function(...Object.keys(deps), ...args, block(download, 'private ' + name + '(').body);
    state[name] = (...values) => method.call(state, ...Object.values(deps), ...values);
  }
  state.updateSceneContentWidth(windowWidth);
  return state;
}

function layoutFrames(state, expectedSplit) {
  for (let frame = 0; frame < 12; frame++) {
    const declared = rootWidth.call(state);
    const measured = declared === '100%' ? state.windowWidth : declared;
    // Run the actual scene area-change path with the width its root requests.
    state.updateSceneContentWidth(measured);
    assert.equal(state.sceneContentWidth, state.windowWidth, 'pane width must never become scene width');
    assert.equal(state.useSplitLayout(), expectedSplit, 'split mode must not oscillate between layout frames');
    state.updateDownloadContentWidthFromArea(state.downloadContentWidth);
    assert.equal(state.sceneContentWidth, state.windowWidth, 'child measurement must not change scene width');
    if (expectedSplit) {
      assert.equal(state.downloadContentWidth, state.splitListPaneWidth());
      assert.equal(state.splitListPaneWidth() + 1 + state.splitSidePaneWidth(), state.windowWidth);
    }
  }
}

test('opening and closing download detail never feeds the left pane width back into the scene', () => {
  for (const width of [600, breakpoint, 1024, 1440, 2560]) {
    for (const ratio of [0.25, 0.42, 0.75]) {
      const state = model(width);
      state.splitListRatio = ratio;
      for (const open of [true, false, true, false]) {
        state.showDetail = open;
        state.syncDownloadContentWidthForCurrentLayout();
        layoutFrames(state, open && width >= breakpoint);
      }
      assert.deepEqual(state.rememberedWidths, [width]);
    }
  }
});

test('folding, resizing, label manager and disabled split mode use the full host measurement', () => {
  for (const enabled of [true, false]) {
    const state = model(1200, enabled);
    for (const pane of ['showDetail', 'downloadLabelManagerVisible']) {
      state[pane] = true;
      for (const width of [1200, 720, 839, 840, 1600, 600, 1200]) {
        state.windowWidth = width;
        state.updateSceneContentWidth(width);
        layoutFrames(state, enabled && width >= breakpoint);
      }
      state[pane] = false;
    }
  }
});

test('only the list pane resizes; detail, divider, reader and modal overlays are root siblings', () => {
  const pane = block(download, 'private downloadListPane()').body;
  assert.match(pane, /\.width\(this\.useSplitLayout\(\) \? this\.splitListPaneWidth\(\) : '100%'\)/);
  assert.match(pane, /GalleryHomeNavBarHost\(/);
  assert.match(pane, /FloatingActionDock\(/);
  assert.match(pane, /this\.activeSplitPane = SPLIT_PANE_FOCUS_LEFT/);
  assert.match(pane, /handleOpenDownloadLabelDrawerPan/);
  assert.doesNotMatch(pane, /GalleryDetailHostScene\(|ReaderSessionScene\(|SplitPaneDivider\(|BlockingBusyOverlay\(|updateSceneContentWidth\(/);
  for (const child of ['this.downloadListPane()', 'GalleryDetailHostScene(', 'SplitPaneDivider(',
    'ReaderSessionScene(', 'BlockingBusyOverlay(']) {
    assert.ok(root.body.includes(child), child);
  }
  assert.match(root.tail, /updateSceneContentWidth\(areaDimensionToVp/);
  assert.doesNotMatch(root.tail, /\.animation\(|\.onTouch\(|\.gesture\(/);
});

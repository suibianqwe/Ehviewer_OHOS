import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const host = read('components/ReaderHostScene.ets');
const scene = read('components/ReaderScenes.ets');
const downloads = read('components/DownloadScene.ets');
const toolbar = read('components/DownloadComponents.ets');
const sortSource = read('services/DownloadSortSupport.ets');
const erase = text => text.replace(/^import .*;\n/gm, '').replace(/\b(?:export|private) /g, '')
  .replace(/: Promise<ReaderSourceImageSize>\[\]/g, '')
  .replace(/: Promise<[^>]+>/g, '')
  .replace(/: (?:DownloadInfo|common.UIAbilityContext|GalleryPreview|GalleryPage|number|string|boolean|void)\b(?:\[\])?/g, '')
  .replace(/: Map<number, string>/g, '').replace(/new Map<number, string>/g, 'new Map')
  .replace(/: DownloadSortKey/g, '')
  .replace(/const requests: Promise<ReaderSourceImageSize>\[\]/g, 'const requests');
function method(text, name) {
  const start = text.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(text.slice(start, text.indexOf('\n  }', start) + 4));
}
const { sortDownloadItems, normalizeDownloadSortMode, options } = Function(erase(sortSource) +
  '\nreturn {sortDownloadItems, normalizeDownloadSortMode, options: DOWNLOAD_SORT_OPTIONS};')();

const item = (gid, fields = {}) => ({ gid, title: 'Title ' + gid, time: gid * 100, rating: gid / 10,
  fileSize: gid * 10, ...fields });

test('all download order options work in both directions with deterministic GID tie breaking', () => {
  const items = [item(3), item(1), item(2)];
  for (const field of ['GID', 'Time', 'Rating', 'Name', 'Size']) {
    for (const direction of ['asc', 'desc']) {
      const copy = items.slice();
      sortDownloadItems(copy, field + ' ' + direction);
      assert.deepEqual(copy.map(i => i.gid), direction === 'asc' ? [1, 2, 3] : [3, 2, 1]);
    }
  }
  for (const mode of ['Default', 'Time desc']) {
    const copy = items.slice(); sortDownloadItems(copy, mode);
    assert.deepEqual(copy.map(i => i.gid), [3, 2, 1]);
  }
  const tied = [item(1, { time: 0 }), item(3, { time: 0 }), item(2, { time: 0 })];
  sortDownloadItems(tied, 'Time asc');
  assert.deepEqual(tied.map(i => i.gid), [3, 2, 1]);
  assert.deepEqual(items.map(i => i.gid), [3, 1, 2], 'sorting a filtered copy never reorders the download queue');
});

test('author sorting uses namespaced artist tags, handles multiple artists and keeps unknowns last', () => {
  const items = [
    item(1, { detailTags: [{ namespace: 'artist', tags: ['Beta', 'Alpha'] }] }),
    item(2, { simpleTags: ['artist:Beta'] }),
    item(3, { tagList: ['Artist:Gamma'] }),
    item(4, { uploader: 'AAAA', detailTags: [{ namespace: 'group', tags: ['AAAA'] }] }),
    item(5)
  ];
  for (const [mode, ids] of [['Author asc', [1, 2, 3, 5, 4]], ['Author desc', [3, 2, 1, 5, 4]]]) {
    const copy = items.slice(); sortDownloadItems(copy, mode);
    assert.deepEqual(copy.map(i => i.gid), ids);
  }
  assert.deepEqual(items[0].detailTags[0].tags, ['Beta', 'Alpha']);
});

test('sorting is exposed once with and without selections and optional translation actions', () => {
  const model = Function('return {' + ['actionCount', 'actionKind'].map(n => method(toolbar, n)).join(',') + '};')();
  for (const selected of [false, true]) for (const translate of [false, true]) {
    Object.assign(model, { expanded: true, hasSelection: selected, showTranslationButton: translate });
    const actions = Array.from({ length: model.actionCount() }, (_, i) => model.actionKind(i));
    assert.equal(actions.filter(a => a === 'sort').length, 1);
    assert.equal(new Set(actions).size, actions.length);
    assert.ok(!actions.includes(''));
    assert.equal(actions.includes('translate'), translate);
  }
  assert.match(downloads, /SettingsOptionPanel\(\{\s*title: 'Sort'/);
  assert.match(downloads, /onSort: \(\) =>/);
  assert.match(method(downloads, 'applyDownloadSort'), /ehSettingsStore\.setValue\(DOWNLOAD_SORT_SETTING_KEY/);
  assert.match(downloads, /normalizeDownloadSortMode\(ehSettingsStore.getValue\(DOWNLOAD_SORT_SETTING_KEY/);
  for (const option of options) assert.equal(normalizeDownloadSortMode(option), option);
  assert.equal(normalizeDownloadSortMode('obsolete'), 'Default');
});

const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { resolve, promise }; };
function metadataModel({ enabled = true, nextExists = true } = {}) {
  const requests = [];
  const prepare = Function('ehSettingsStore', 'ehDownloadFileStore', 'readReaderSourceImageSize',
    'cloneGalleryPreviews', 'cloneGalleryDetail', 'return {' + method(host, 'prepareDownloadedSpreadSizes') +
    '}.prepareDownloadedSpreadSizes;')(
    { getValue: () => enabled ? 'On' : 'Off' }, { findPageImage: (_ctx, _detail, index) => nextExists ? '/' + index + '.jpg' : '' },
    path => { const pending = deferred(); requests.push({ path, ...pending }); return pending.promise; },
    p => p.map(v => ({ ...v })), d => ({ ...d }));
  const state = { detail: { gid: 123, previewSet: Array.from({ length: 4 }, (_, index) => ({ index, width: 0, height: 0 })) },
    readerTotalPages: () => 4, downloadedImageSizes: new Map(), readerSceneActive: true, loadedSessionRevision: 1,
    seeded: [], seedReaderPreviewCache(previews) { this.seeded.push(previews); }, prepareDownloadedSpreadSizes: prepare };
  return { state, requests, prepare };
}

test('local automatic spread metadata reads at most current+next and shares adjacent requests', async () => {
  const h = metadataModel();
  const first = h.prepare.call(h.state, {}, 0, '/0.jpg');
  const second = h.prepare.call(h.state, {}, 1, '/1.jpg');
  assert.deepEqual(h.requests.map(r => r.path), ['/0.jpg', '/1.jpg', '/2.jpg']);
  assert.equal(h.state.seeded.length, 0, 'do not publish partial headers');
  for (const request of h.requests) request.resolve({ width: 800, height: 1200 });
  await Promise.all([first, second]);
  for (const preview of h.state.detail.previewSet.slice(0, 3)) {
    assert.equal(preview.width, 800); assert.equal(preview.height, 1200);
  }
  await h.prepare.call(h.state, {}, 0, '/0.jpg');
  assert.equal(h.requests.length, 3);
  assert.doesNotMatch(method(host, 'prepareDownloadedSpreadSizes'), /createPixelMap|Sync\(/);
});

test('disabled dual-page mode does no header work; damaged/missing next pages cannot block the current page', async () => {
  const disabled = metadataModel({ enabled: false });
  await disabled.prepare.call(disabled.state, {}, 0, '/0.jpg');
  assert.equal(disabled.requests.length, 0);
  const h = metadataModel({ nextExists: false });
  const pending = h.prepare.call(h.state, {}, 0, '/0.jpg');
  assert.equal(h.requests.length, 1);
  h.requests[0].resolve({ width: 0, height: 0 }); await pending;
  assert.equal(h.state.seeded.length, 0);
  assert.equal(h.state.downloadedImageSizes.size, 0, 'failed headers may be retried');
});

test('old header results never update a closed, different-gallery or newer session', async () => {
  for (const change of [s => { s.readerSceneActive = false; }, s => { s.detail.gid = 456; },
    s => { s.loadedSessionRevision++; }]) {
    const h = metadataModel();
    const pending = h.prepare.call(h.state, {}, 0, '/0.jpg');
    change(h.state);
    h.requests.forEach(r => r.resolve({ width: 800, height: 1200 }));
    await pending;
    assert.equal(h.state.seeded.length, 0);
    assert.ok(h.state.detail.previewSet.every(p => p.width === 0));
  }
});

test('download pixels wait for both headers and grouping uses a persistent spread viewport', async () => {
  const steps = [], pending = deferred();
  const useLocal = Function('ehDownloadFileStore', 'readerPageSourceGuard', 'cloneGalleryPage',
    'return {' + method(host, 'tryUseDownloadedPage') + '}.tryUseDownloadedPage;')(
    { findPageImage: () => '/0.jpg' }, { isPreview: async () => false }, p => p);
  const state = { detail: { gid: 123, previewSet: [] }, readerContext: () => ({}), readerSceneActive: true,
    loadedSessionRevision: 1, pageIndex: 0, renderVersion: 0,
    async prepareDownloadedSpreadSizes() { steps.push('headers'); await pending.promise; steps.push('group-ready'); },
    setReaderPage() { steps.push('pixels'); } };
  const result = useLocal.call(state, 0, { pageUrl: 'ehviewer://download/123/0' });
  await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(steps, ['headers']);
  pending.resolve(); assert.equal(await result, true);
  assert.deepEqual(steps, ['headers', 'group-ready', 'pixels']);
  assert.match(scene, /if \(this\.shouldRenderPageGroup\(index\)\) \{\s*this\.ReaderSpreadPage\(index, key\)/);
  assert.doesNotMatch(scene, /paired === this\.shouldPairPage\(index\)/);
  assert.match(method(scene, 'onReaderPreviewsChange'), /schedulePageGroupRefresh\(0\)/);
});

test('header classification updates the spread before source rendering, but never regroups mid-swipe', () => {
  const watch = Function('return {' + method(scene, 'onReaderPreviewsChange') + '}.onReaderPreviewsChange;')();
  const calls = [];
  const state = { cropWhiteBorders: false, readerWindowActive: true, swiperAnimating: false,
    syncReaderPreviewImageSizes: () => true, refreshPageGroups: () => calls.push('now'),
    schedulePageGroupRefresh: delay => calls.push(delay) };
  watch.call(state);
  assert.deepEqual(calls, ['now']);
  state.swiperAnimating = true;
  watch.call(state);
  assert.deepEqual(calls, ['now', 0]);
  state.cropWhiteBorders = true;
  watch.call(state);
  assert.equal(calls.length, 2, 'original header dimensions cannot override cropped dimensions');
});

test('download settings wait for the cold-start store and ignore navigation during that wait', async () => {
  const panels = read('components/SettingsPanels.ets');
  const start = panels.indexOf('export struct SettingsDetailPanel');
  const refresh = method(panels.slice(start), 'refreshStorageStatistics')
    .replace(/const panel: SettingsPanel/g, 'const panel');
  let scans = 0;
  for (const leave of [false, true]) {
    const loaded = deferred();
    const state = { mounted: true, statisticsRequestId: 1, panel: 'download', rebuildSettingsRows() {} };
    const run = Function('getAbilityContext', 'SettingsPanel', 'readerImageCache', 'ehDownloadStore',
      'ehDownloadFileStore', 'downloadSizeText', 'return {' + refresh + '}.refreshStorageStatistics;')(
      () => ({}), { Advanced: 'advanced', Download: 'download' }, {},
      { ensureLoaded: () => loaded.promise, getGalleryIds: () => [10] },
      { async scanRedundantDirectoriesAsync(_ctx, gids) { assert.deepEqual(gids, [10]); scans++; return { bytes: 0 }; } },
      n => n.toString());
    const before = scans;
    const pending = run.call(state, 1);
    assert.equal(scans, before);
    if (leave) state.mounted = false;
    loaded.resolve(); await pending;
    assert.equal(scans, before + (leave ? 0 : 1));
  }
});

test('concurrent settings initialization shares one promise and failures remain retryable', async () => {
  const ensure = Function('return {' + method(read('services/EhSettingsStore.ets'), 'ensureLoaded') + '}.ensureLoaded;')();
  const pending = deferred(); let loads = 0;
  const state = { loaded: false, ensurePromise: null, load: () => { loads++; return pending.promise; } };
  const first = ensure.call(state, {}), second = ensure.call(state, {});
  assert.equal(first, second);
  assert.equal(loads, 1);
  pending.resolve(); await first;
  assert.equal(state.loaded, true); assert.equal(state.ensurePromise, null);
  await ensure.call(state, {}); assert.equal(loads, 1);
  state.loaded = false;
  state.load = async () => { throw new Error('load'); };
  await assert.rejects(ensure.call(state, {}), /load/);
  assert.equal(state.loaded, false); assert.equal(state.ensurePromise, null);
  state.load = async () => { loads++; };
  await ensure.call(state, {}); assert.equal(loads, 2);
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const panels = read('components/SettingsPanels.ets');
const detail = panels.slice(panels.indexOf('export struct SettingsDetailPanel'),
  panels.indexOf('export struct SettingsOptionPanel'));
const cache = read('services/ReaderImageCache.ets');
const downloads = read('services/EhDownloadFileStore.ets');
const shared = read('shared/EhShared.ets');
const scene = read('components/SettingsScene.ets');

function erase(text) {
  return text.replace(/\b(?:private|export) /g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:common.UIAbilityContext|SettingsRowItem|SettingsPanel|CacheClearResult|DownloadDirectoryScanResult|RestoredGalleryData|GalleryMetadata|AndroidSpiderInfo|string|number|boolean|void)\b(?:\[\])?(?: \| null)?/g, '')
    .replace(/ as GalleryMetadata/g, '')
    .replace(/new Set<number>/g, 'new Set');
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function func(source, name) {
  const start = source.search(new RegExp('^(?:export )?(?:async )?function ' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n}', start) + 2));
}
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const Panel = { Advanced: 'advanced', Download: 'download', Eh: 'eh' };

function model() {
  const timers = new Map(), requests = [];
  let sequence = 0, builds = 0;
  const names = ['rebuildSettingsRows', 'onPanelChanged', 'onRenderRevisionChanged', 'onSettingEntriesChanged',
    'cancelStorageStatistics', 'scheduleStorageStatistics', 'refreshStorageStatistics',
    'aboutToDisappear', 'isFirstSettingsRow', 'isLastSettingsRow'];
  const state = Function('SettingsPanel', 'settingsRowsForPanel', 'getAbilityContext', 'downloadSizeText',
    'readerImageCache', 'ehDownloadFileStore', 'ehDownloadStore', 'setTimeout', 'clearTimeout', 'settingEntryValue',
    'return {' + names.map(name => method(detail, name)).join(',\n') + '};')(
      Panel, (_panel, _theme, _entries, cacheSize, redundantSize) => {
        builds++;
        return [{ type: 'action', value: cacheSize }, { type: 'action', value: redundantSize }];
      }, () => ({}), bytes => bytes + ' B',
      { sizeAsync() { const request = deferred(); requests.push(request); return request.promise; } },
      { scanRedundantDirectoriesAsync(_context, gids) {
        assert.deepEqual(gids, [12, 34]);
        const request = deferred(); requests.push(request); return request.promise;
      } }, { ensureLoaded: async () => {}, getGalleryIds: () => [12, 34] },
      (callback) => { const id = ++sequence; timers.set(id, callback); return id; },
      id => timers.delete(id), (entries, key, fallback) => entries.find(entry => entry.key === key)?.value ?? fallback);
  return Object.assign(state, {
    mounted: true, statisticsTimer: -1, statisticsRequestId: 0,
    panel: Panel.Advanced, themeName: 'Light', settingEntries: [],
    readerCacheSizeText: '...', downloadRedundancyText: '...', statisticsDownloadLocation: 'App files', rows: [],
    timers, requests, builds: () => builds,
    runTimers() { const callbacks = [...timers.values()]; timers.clear(); callbacks.forEach(callback => callback()); }
  });
}

test('settings row construction has no directory scans or filesystem work', () => {
  const body = func(shared, 'settingsRowsForPanel');
  assert.doesNotMatch(body, /currentReaderCacheSizeText|currentDownloadRedundancyText|\.size\(|scanRedundant|fs\./);
  assert.match(body, /readerCacheSizeText/);
  assert.match(body, /downloadRedundancyText/);
  assert.doesNotMatch(detail, /this\.settingsRows\(/);
});

test('rendering all row boundaries reuses one snapshot instead of rebuilding per row', () => {
  const state = model();
  state.rebuildSettingsRows();
  for (let i = 0; i < 100; i++) {
    state.isFirstSettingsRow(0);
    state.isLastSettingsRow(1);
  }
  assert.equal(state.builds(), 1);
  assert.equal(state.requests.length, 0);
  assert.equal(state.isFirstSettingsRow(0), true);
  assert.equal(state.isLastSettingsRow(1), true);
});

test('opening advanced renders immediately and coalesces size refreshes until after transition', async () => {
  const state = model();
  state.onPanelChanged();
  state.onRenderRevisionChanged();
  assert.equal(state.rows[0].value, '...');
  assert.equal(state.requests.length, 0);
  assert.equal(state.timers.size, 1);
  state.runTimers();
  assert.equal(state.requests.length, 1);
  state.requests[0].resolve({ bytes: 1234 });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(state.rows[0].value, '1234 B');
  state.settingEntries = [{ key: 'dns_over_https', value: 'On' }];
  state.rebuildSettingsRows();
  assert.equal(state.requests.length, 1);
});

test('late results cannot overwrite another panel, a new refresh or an exited component', async () => {
  for (const change of [
    state => { state.panel = Panel.Eh; state.onPanelChanged(); },
    state => state.onRenderRevisionChanged(),
    state => state.aboutToDisappear()
  ]) {
    const state = model();
    state.onPanelChanged();
    state.runTimers();
    change(state);
    const builds = state.builds();
    state.requests[0].resolve({ bytes: 9876 });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(state.readerCacheSizeText, '...');
    assert.equal(state.builds(), builds);
  }
});

test('download statistics use only IDs and async scanning; leaving cancels scheduled work', async () => {
  const state = model();
  state.panel = Panel.Download;
  state.onPanelChanged();
  state.runTimers();
  await Promise.resolve();
  state.requests[0].resolve({ bytes: 56 });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(state.rows[1].value, '56 B');
  state.onRenderRevisionChanged();
  state.aboutToDisappear();
  state.runTimers();
  assert.equal(state.requests.length, 1);
  assert.doesNotMatch(method(detail, 'refreshStorageStatistics'), /getItems\(/);
});

test('only a download location change invalidates its size when editing settings', () => {
  const state = model();
  state.panel = Panel.Download;
  state.downloadRedundancyText = '100 B';
  state.settingEntries = [{ key: 'download_thread', value: '8' }];
  state.onSettingEntriesChanged();
  assert.equal(state.timers.size, 0);
  assert.equal(state.downloadRedundancyText, '100 B');
  state.settingEntries = [{ key: 'download_location', value: 'Downloads' }];
  state.onSettingEntriesChanged();
  assert.equal(state.downloadRedundancyText, '...');
  assert.equal(state.timers.size, 1);
});

test('cache statistics use async I/O, ignore temporary files/directories and tolerate concurrent deletion', async () => {
  const reads = [];
  const fs = {
    async listFile(dir) {
      reads.push(dir);
      return dir === '/new' ? ['a', 'active.part', 'folder', 'removed'] : ['b'];
    },
    async stat(path) {
      assert.ok(!path.endsWith('.part'));
      if (path.endsWith('removed')) throw new Error('removed');
      return { size: path.endsWith('a') ? 10 : 20, isDirectory: () => path.endsWith('folder') };
    }
  };
  const sizeAsync = Function('fs', 'readerImageCacheDirectory', 'legacyReaderImageCacheDirectory',
    'return {' + method(cache, 'sizeAsync') + '}.sizeAsync;')(fs, () => '/new', () => '/legacy');
  assert.doesNotMatch(method(cache, 'sizeAsync'), /Sync\(/);
  assert.deepEqual(await sizeAsync({}), { files: 2, bytes: 30 });
  assert.deepEqual(reads, ['/new', '/legacy']);
});

test('download metadata parsers accept HarmonyOS, legacy JSON and Android formats without writes', async () => {
  const metadata = { gid: 10, token: 'test', title: 'test', pages: 20 };
  const contents = new Map([
    ['/new/.ehviewer.json', JSON.stringify(metadata)],
    ['/old/.ehviewer', JSON.stringify(metadata)],
    ['/android/.ehviewer', 'VERSION2\n00000000\n10\ntest\n1\n2\n0\n20\n']
  ]);
  const load = Function('fs', 'OHOS_METADATA_FILENAME', 'ANDROID_SPIDER_INFO_FILENAME',
    'metadataToGallery', 'spiderInfoToGallery', 'parseInteger',
    func(downloads, 'parseMetadata') + '\n' + func(downloads, 'parseAndroidSpiderInfo') + '\n' +
    func(downloads, 'readRestoredGalleryAsync') + '\nreturn readRestoredGalleryAsync;')(
      { async readText(path) { if (!contents.has(path)) throw new Error('not found'); return contents.get(path); } },
      '.ehviewer.json', '.ehviewer', value => value, value => value,
      (value, fallback) => Number.isNaN(parseInt(value, 10)) ? fallback : parseInt(value, 10));
  assert.doesNotMatch(func(downloads, 'readRestoredGalleryAsync'), /Sync\(|writeText|migrat/);
  for (const path of ['/new', '/old', '/android']) {
    const result = await load(path, path);
    assert.equal(result.gallery.gid, 10);
    assert.equal(result.total, 20);
  }
  assert.equal(await load('/missing', 'missing'), null);
});

test('redundant download statistics skip retained and unrecognized galleries without deleting anything', async () => {
  const scanned = [];
  const scan = Function('fs', 'readRestoredGalleryAsync', 'scanDirectoryTreeAsync',
    'return {' + method(downloads, 'scanRedundantDirectoriesAsync') + '}.scanRedundantDirectoriesAsync;')(
      { listFile: async () => ['keep', 'orphan', 'unknown', 'removed'] },
      async path => path.endsWith('unknown') ? null : { gallery: { gid: path.endsWith('keep') ? 1 : 2 } },
      async path => {
        scanned.push(path);
        if (path.endsWith('removed')) throw new Error('removed');
        return { directories: 2, files: 3, bytes: 100 };
      });
  assert.deepEqual(await scan.call({ downloadRoot: () => '/root' }, {}, [1]),
    { directories: 2, files: 3, bytes: 100 });
  assert.deepEqual(scanned, ['/root/orphan', '/root/removed']);
  assert.doesNotMatch(method(downloads, 'scanRedundantDirectoriesAsync'), /Sync\(|removeDirectory\w*\(|writeText\w*\(/);
});

test('settings reuse loaded downloads instead of reparsing and rebroadcasting the entire store', () => {
  const aboutToAppear = method(scene, 'aboutToAppear');
  assert.match(aboutToAppear, /ehDownloadStore.ensureLoaded\(context\)/);
  assert.doesNotMatch(aboutToAppear, /ehDownloadStore.load\(context\)/);
});

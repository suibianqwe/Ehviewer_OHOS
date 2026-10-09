import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const favoritesSource = read('services/GalleryListParser.ets');
const detailSource = read('components/GalleryDetailHostScene.ets');
const downloadSource = read('services/EhDownloadFileStore.ets');
const settingsSource = read('components/SettingsPanels.ets');
const sceneSource = read('components/SettingsScene.ets');

// Run the production logic, erasing just the annotations used by these helpers (Node 20 compatible).
function erase(source) {
  return source.replace(/\bexport |\bprivate /g, '')
    .replace(/onProgress\?: \(progress: DownloadMigrationProgress\) => void/g, 'onProgress')
    .replace(/:\s*Promise<[^>]+>/g, '')
    .replace(/: (?:common\.UIAbilityContext|DownloadMigrationProgressState|DownloadMigrationProgress|FavoriteCategoryInfo|FavoriteSlotOption|SettingsRowItem|GallerySite|RegExpExecArray|string|number|boolean|void)\b(?:\[\])?(?: \| null)?/g, '');
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

function loadFunctions(source, names, dependencies = {}) {
  return Function(...Object.keys(dependencies), names.map((name) => functionSource(source, name)).join('\n') +
    '\nreturn {' + names.join(',') + '};')(...Object.values(dependencies));
}

function loadMethods(source, names, dependencies = {}) {
  return Function(...Object.keys(dependencies), 'return {' +
    names.map((name) => methodSource(source, name)).join(',\n') + '};')(...Object.values(dependencies));
}

const { decodeHtmlEntities } = loadFunctions(read('shared/HtmlEntitySupport.ets'),
  ['decodeHtmlEntities', 'decodeHtmlEntitiesOnce', 'decodeHtmlEntity', 'decodeNumericHtmlEntity']);
const { parseFavoriteCategories } = loadFunctions(favoritesSource,
  ['parseFavoriteCategories', 'findFirstTagBlock', 'childDivs', 'cleanText', 'decodeHtml', 'parseIntSafe'],
  { decodeHtmlEntities });
const { favoriteSlotOptions } = loadFunctions(read('services/FavoriteCollectionSupport.ets'), ['favoriteSlotOptions']);
const categoryHtml = (slot, name, count = 2) => `<div class="fp" onclick="document.location='favorites.php?favcat=${slot}'">
  <div>${count}</div><div class="i"></div><div>${name}</div></div>`;

test('#29 renamed collections share the favorites parser and retain their actual slot IDs', () => {
  const parsed = parseFavoriteCategories(categoryHtml(8, 'A &amp; B') + categoryHtml(2, '&#x6536;&#x85cf;') +
    categoryHtml(0, '<span>First</span>'));
  assert.deepEqual(parsed, [
    { favCat: 8, name: 'A & B', count: 2 }, { favCat: 2, name: '收藏', count: 2 },
    { favCat: 0, name: 'First', count: 2 }
  ]);
  const options = favoriteSlotOptions(parsed);
  assert.equal(options.length, 11);
  assert.deepEqual(options[0], { slot: -1, label: 'Local Favorites' });
  assert.deepEqual(options[3], { slot: 2, label: '收藏' });
  assert.deepEqual(options[9], { slot: 8, label: 'A & B' });
  assert.deepEqual(options[2], { slot: 1, label: 'Favorites 1' });
});

test('#29 ignores All, invalid, blank and duplicate collections without shifting subsequent slots', () => {
  const parsed = parseFavoriteCategories(categoryHtml('all', 'All') + categoryHtml(15, 'Invalid') +
    categoryHtml(1, '  ') + categoryHtml(4, 'Actual') + categoryHtml(4, 'Duplicate') + categoryHtml(9, 'Last'));
  assert.deepEqual(parsed.map(({ favCat, name }) => [favCat, name]), [[4, 'Actual'], [9, 'Last']]);
  assert.equal(favoriteSlotOptions(parseFavoriteCategories('<p>Sign in required</p>'))[10].label, 'Favorites 9');
});

test('#29 fetches fresh names on the selected site without loading gallery API metadata', async () => {
  const urls = {
    getFavoritesUrl: (site) => site + '/favorites.php', getReferer: (site) => site + '/'
  };
  const client = loadMethods(read('services/EhHttpClient.ets'), ['loadFavoriteCategories'],
    { EhUrl: urls, parseFavoriteCategories, httpStatusMessage: (status) => 'HTTP ' + status });
  const calls = [];
  client.getText = async (...args) => {
    calls.push(args);
    return { statusCode: 200, body: categoryHtml(3, calls.length === 1 ? 'Old' : 'Renamed') };
  };
  assert.equal((await client.loadFavoriteCategories('ex'))[0].name, 'Old');
  assert.equal((await client.loadFavoriteCategories('ex'))[0].name, 'Renamed');
  assert.deepEqual(calls, [['ex/favorites.php', 'ex/', 0], ['ex/favorites.php', 'ex/', 0]]);
  client.getText = async () => ({ statusCode: 403, body: '' });
  await assert.rejects(client.loadFavoriteCategories('ex'), /HTTP 403/);
});

function favoriteDialog() {
  let generation = 0;
  const pending = [];
  const state = loadMethods(detailSource, ['showAddFavoriteDialog'], {
    parseDefaultFavoriteSlot: () => null, ehSettingsStore: { getValue: () => 'Ask' },
    DEFAULT_FAVORITE_SLOT_SETTING_KEY: 'default', DEFAULT_FAVORITE_SLOT_ASK: 'Ask'
  });
  Object.assign(state, {
    detail: { gid: 1, token: 'token' }, detailLink: { site: 'ex' }, renderVersion: 0,
    favoriteCategoryRequestGate: { begin: () => ++generation, isCurrent: (value) => value === generation },
    client: { loadFavoriteCategories: () => new Promise((resolve, reject) => pending.push({ resolve, reject })) }
  });
  return { state, pending };
}

test('#29 late category responses cannot overwrite a reopened dialog, different gallery, or closed dialog', async () => {
  const { state, pending } = favoriteDialog();
  state.showAddFavoriteDialog();
  state.showAddFavoriteDialog();
  pending[1].resolve([{ favCat: 0, name: 'Latest' }]);
  await Promise.resolve();
  pending[0].resolve([{ favCat: 0, name: 'Stale' }]);
  await Promise.resolve();
  assert.equal(state.favoriteCategories[0].name, 'Latest');
  for (const invalidate of [() => state.detail.gid++, () => { state.addFavoriteDialogVisible = false; },
    () => state.favoriteCategoryRequestGate.begin(), () => { state.detailLink.site = 'e'; }]) {
    state.showAddFavoriteDialog();
    invalidate();
    pending.at(-1).resolve([{ favCat: 0, name: 'Stale' }]);
    await Promise.resolve();
    assert.deepEqual(state.favoriteCategories, []);
  }
  state.showAddFavoriteDialog();
  pending.at(-1).reject(new Error('offline'));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(state.addFavoriteDialogVisible, true);
  assert.equal(favoriteSlotOptions(state.favoriteCategories).length, 11);
});

const { settingsRowRenderKey } = loadFunctions(read('components/SettingsSupport.ets'), ['settingsRowRenderKey']);
const switchMethods = loadMethods(settingsSource, ['onRowChanged', 'onSwitchValueChanged', 'changeSwitch']);
function settingsRow(value = 'Off', type = 'switch') {
  return { ...switchMethods, row: { key: 'follow_system_dark_mode', title: 'Follow system', type, value },
    switchValue: value, inputValue: '', committedInputValue: '', writes: [], onSwitchChange(key, isOn) {
      this.writes.push([key, isOn]);
      this.switchValue = isOn ? 'On' : 'Off';
      this.onSwitchValueChanged();
    } };
}

test('#32 switch identity stays stable across state/theme refresh, but localized labels can rebuild', () => {
  const { row } = settingsRow();
  assert.equal(settingsRowRenderKey(row), settingsRowRenderKey({ ...row, value: 'On' }));
  assert.notEqual(settingsRowRenderKey(row), settingsRowRenderKey({ ...row, title: '跟随系统深色模式' }));
  assert.notEqual(settingsRowRenderKey(row), settingsRowRenderKey({ ...row, key: 'another' }));
  assert.match(settingsSource, /@Prop @Watch\('onRowChanged'\) row:/);
  assert.match(settingsSource, /Toggle\(\{ type: ToggleType.Switch, isOn: \$\$this\.switchOn \}\)/);
});

test('#32 immediate toggle state and persisted state agree after repeated theme refreshes', () => {
  const state = settingsRow();
  state.onSwitchValueChanged();
  assert.equal(state.switchOn, false);
  for (const value of [true, false, true, false]) {
    state.changeSwitch(value);
    assert.equal(state.switchOn, value);
    assert.equal(state.switchValue, value ? 'On' : 'Off');
    // ForEach may retain its initial row even though the parent entries have changed.
    state.onRowChanged();
    assert.equal(state.switchOn, value);
    state.changeSwitch(value); // Programmatic synchronization must not persist twice.
  }
  assert.equal(state.writes.length, 4);
  state.switchValue = 'On';
  state.onSwitchValueChanged();
  assert.equal(state.switchOn, true);
  assert.equal(state.writes.length, 4);
});

test('#32 both settings branches bind switch values to current parent entries, not captured ForEach rows', () => {
  assert.equal((settingsSource.match(/switchValue: settingEntryValue\(this\.settingEntries, row\.key \?\? '', row\.value\)/g) ?? []).length, 2);
  assert.match(settingsSource, /@Prop @Watch\('onSwitchValueChanged'\) switchValue:/);
});

test('#32 reactive row synchronization preserves an unsaved text draft during unrelated refresh', () => {
  const state = settingsRow('saved', 'input');
  state.onRowChanged();
  state.inputValue = 'draft';
  state.row = { ...state.row };
  state.onRowChanged();
  assert.equal(state.inputValue, 'draft');
  state.row = { ...state.row, value: 'external update' };
  state.onRowChanged();
  assert.equal(state.inputValue, 'external update');
});

// In-memory file API only: these tests never move/delete the user's downloaded files.
function migrationHarness(options = {}) {
  const nodes = new Map();
  const removed = [];
  const directories = ['/public', '/public/gallery', '/app'];
  for (const path of directories) nodes.set(path, { directory: true, size: 0, mtime: 1 });
  for (const [path, size] of [['/public/gallery/001.jpg', 20], ['/public/gallery/002.jpg', 30]]) {
    nodes.set(path, { directory: false, size, mtime: 1 });
  }
  const statSync = (path) => {
    const node = nodes.get(path);
    if (!node) throw new Error('ENOENT ' + path);
    return { ...node, isDirectory: () => node.directory };
  };
  const listFile = async (path) => [...nodes.keys()].filter((candidate) => candidate.startsWith(path + '/') &&
    !candidate.slice(path.length + 1).includes('/')).map((candidate) => candidate.slice(path.length + 1));
  const fs = {
    statSync, stat: async (path) => statSync(path), accessSync: (path) => nodes.has(path), listFile,
    mkdirSync: (path) => nodes.set(path, { directory: true, size: 0, mtime: 1 }),
    copyFile: async (source, target) => {
      if (options.failCopy === source) throw new Error('copy denied');
      nodes.set(target, { ...nodes.get(source) });
      if (options.truncate === source) nodes.get(target).size--;
      if (options.changeDuringCopy === source) nodes.get(source).mtime++;
    },
    unlink: async (path) => {
      if (options.denyUnlink === path) throw new Error('unlink denied');
      removed.push(path);
      nodes.delete(path);
    },
    rmdir: async (path) => {
      assert.notEqual(path, '/public', 'must never try to delete the selected/public root');
      assert.notEqual(path, '/app', 'must never try to delete the app download root');
      assert.equal((await listFile(path)).length, 0, 'only empty subdirectories may be removed');
      removed.push(path);
      nodes.delete(path);
    }
  };
  const helpers = loadFunctions(downloadSource, ['scanDirectoryTreeAsync', 'copyDirectoryTreeAsync',
    'removeDirectoryTreeAsync', 'cleanupMigratedDownloadFiles', 'reportDownloadMigrationProgress',
    'normalizePath', 'ensureDirectory', 'exists', 'isDirectory'], { fs });
  const store = loadMethods(downloadSource, ['migrateDownloadLocation'], helpers);
  store.rootForLocation = (_context, location) => location;
  const progress = [];
  const run = (source = '/public', target = '/app') => store.migrateDownloadLocation({}, source, target, (event) => {
    progress.push(event);
    options.onProgress?.(event, nodes);
  });
  return { nodes, removed, run, progress };
}

test('#31 both migration directions copy all content and keep the authorized source root', async () => {
  const h = migrationHarness();
  let result = await h.run('/public/', '/app/');
  assert.deepEqual(result, { directories: 2, files: 2, bytes: 50, cleanupIncomplete: false });
  assert.ok(h.nodes.has('/public'));
  assert.ok(!h.nodes.has('/public/gallery'));
  assert.equal(h.nodes.get('/app/gallery/002.jpg').size, 30);
  assert.equal(h.progress[0].phase, 'scanning');
  assert.equal(h.progress.at(-1).phase, 'cleaning');
  result = await h.run('/app', '/public');
  assert.equal(result.cleanupIncomplete, false);
  assert.ok(h.nodes.has('/app'));
  assert.equal(h.nodes.get('/public/gallery/001.jpg').size, 20);
});

test('#31 partial copy failure never cleans up source files', async () => {
  const h = migrationHarness({ failCopy: '/public/gallery/002.jpg' });
  await assert.rejects(h.run(), /copy denied/);
  assert.ok(h.nodes.has('/public/gallery/001.jpg'));
  assert.ok(h.nodes.has('/public/gallery/002.jpg'));
  assert.equal(h.nodes.get('/app/gallery/001.jpg').size, 20);
  assert.deepEqual(h.removed, []);
  assert.ok(!h.progress.some((event) => event.phase === 'cleaning'));
});

test('#31 incomplete copies or source changes during copy are not treated as a successful migration', async () => {
  for (const option of ['truncate', 'changeDuringCopy']) {
    const h = migrationHarness({ [option]: '/public/gallery/001.jpg' });
    await assert.rejects(h.run(), /changed or copy is incomplete/);
    assert.deepEqual(h.removed, []);
    assert.ok(h.nodes.has('/public/gallery/001.jpg'));
  }
});

test('#31 cleanup permission denial returns a warning while retaining the complete destination', async () => {
  const h = migrationHarness({ denyUnlink: '/public/gallery/001.jpg' });
  const result = await h.run();
  assert.equal(result.cleanupIncomplete, true);
  assert.equal(result.files, 2);
  assert.ok(h.nodes.has('/public/gallery/001.jpg'));
  assert.equal(h.nodes.get('/app/gallery/001.jpg').size, 20);
  assert.equal(h.nodes.get('/app/gallery/002.jpg').size, 30);
});

test('#31 cleanup only deletes unchanged verified copies, not new/modified source content', async () => {
  const h = migrationHarness({ onProgress(event, nodes) {
    if (event.phase === 'cleaning') {
      nodes.get('/public/gallery/001.jpg').mtime++;
      nodes.set('/public/gallery/new.jpg', { directory: false, size: 7, mtime: 2 });
    }
  } });
  assert.equal((await h.run()).cleanupIncomplete, true);
  assert.ok(h.nodes.has('/public/gallery/001.jpg'));
  assert.ok(h.nodes.has('/public/gallery/new.jpg'));
  assert.ok(!h.nodes.has('/public/gallery/002.jpg'));
});

test('#31 cleanup preserves source if a destination file disappears or changes after copying', async () => {
  const h = migrationHarness({ onProgress(event, nodes) {
    if (event.phase === 'cleaning') nodes.delete('/app/gallery/001.jpg');
  } });
  assert.equal((await h.run()).cleanupIncomplete, true);
  assert.ok(h.nodes.has('/public/gallery/001.jpg'));
});

test('#31 same/absent roots are safe no-ops, overlapping/broad roots are rejected', async () => {
  const h = migrationHarness();
  assert.equal((await h.run('/public', '/public/')).files, 0);
  assert.equal((await h.run('/absent', '/app')).files, 0);
  for (const [source, target] of [['/public', '/public/nested'], ['/public/gallery', '/public'],
    ['/', '/app'], ['/public', '/'], ['', '/app']]) {
    await assert.rejects(h.run(source, target), /Invalid|overlap/);
  }
  assert.deepEqual(h.removed, []);
});

test('#31 settings switch location after successful copy even with cleanup warning, but not on copy failure', async () => {
  for (const outcome of ['success', 'cleanup warning', 'copy failure']) {
    const store = { async migrateDownloadLocation() {
      if (outcome === 'copy failure') throw new Error('copy denied');
      return { files: 2, bytes: 50, cleanupIncomplete: outcome === 'cleanup warning' };
    } };
    const state = loadMethods(sceneSource, ['applyDownloadLocationChangeAsync'],
      { ehDownloadFileStore: store, downloadSizeText: String });
    Object.assign(state, { commits: [], status: '', closeDownloadMigrationDialog() {}, showBlockingBusy() {},
      hideBlockingBusy() {}, ensureDownloadLocationAccess: async () => true, updateDownloadMigrationProgress() {},
      showFloatingStatus(message) { this.status = message; },
      commitSettingValue(key, value) { this.commits.push([key, value]); }
    });
    await state.applyDownloadLocationChangeAsync({}, 'Public', 'App', true);
    assert.deepEqual(state.commits, outcome === 'copy failure' ? [] : [['download_location', 'App']]);
    if (outcome === 'cleanup warning') assert.match(state.status, /Some old files remain/);
    if (outcome === 'copy failure') assert.match(state.status, /migration failed/);
  }
});

test('#31 migration action has a readable foreground on material/blur backgrounds', () => {
  const overlays = read('components/SettingsOverlays.ets');
  const button = overlays.slice(overlays.indexOf("Button(uiText('Migrate')"),
    overlays.indexOf('.onClick(this.onMigrate)'));
  assert.match(button, /\.height\(44\)/);
  assert.match(button, /\.fontColor\(uiMaterialForegroundColor\(themeAccentTextColor\(\)\)\)/);
  assert.doesNotMatch(button, /themeOnPrimaryText/);
});

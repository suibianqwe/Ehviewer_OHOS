import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const storeSource = read('services/EhDownloadStore.ets');
const scene = read('components/DownloadScene.ets');
function erase(text) {
  return text.replace(/^import .*;\n/gm, '').replace(/\b(?:private|export) /g, '')
    .replace(/: \(\) => void/g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: Map<number, (?:DownloadInfo|DownloadSortKey|string)>/g, '')
    .replace(/: (?:DownloadInfo|DownloadLabel|DownloadProgress|DownloadStoreListener|DownloadProgressListener|DownloadStoreSubscription|DownloadSortKey|DownloadChunkFilter|DownloadProgressUpdater|taskpool.Task|number|string|boolean|void|Error)\b(?:\[\])?(?: \| undefined)?/g, '')
    .replace(/\b(onProgress)\?(?=[,)])/g, '$1')
    .replace(/new (Map|Array)<[^>]+>/g, 'new $1')
    .replace(/new Promise<void>/g, 'new Promise')
    .replace(/ as number(?:\[\])?/g, '');
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function methods(source, names, deps = {}) {
  return Function(...Object.keys(deps), 'return {' + names.map(n => method(source, n)).join(',\n') + '};')(
    ...Object.values(deps));
}
const keySource = read('services/DownloadSortKeys.ets').replace(/export interface DownloadSortKey \{[^}]+\}/, '');
const { compareDownloadSortKeys, sortDownloadKeys } = Function(erase(keySource) +
  ';return {compareDownloadSortKeys,sortDownloadKeys};')();
const sortSupport = erase(read('services/DownloadSortSupport.ets'));
const { downloadSortKey, sortDownloadItems, modes } = Function(sortSupport +
  ';return {downloadSortKey,sortDownloadItems,modes:DOWNLOAD_SORT_OPTIONS};')();
const projectionSource = read('services/DownloadListProjection.ets');
const progressStart = projectionSource.indexOf('export function applyDownloadProgressUpdates');
const progressEnd = projectionSource.indexOf('\n}', progressStart) + 2;
const applyDownloadProgressUpdates = Function(erase(projectionSource.slice(progressStart, progressEnd)) +
  ';return applyDownloadProgressUpdates;')();
const item = (gid, fields = {}) => ({ gid, title: 'Title ' + (gid % 97), time: gid % 31,
  rating: gid % 5, fileSize: gid % 1024, state: 'downloading', ...fields });

test('lightweight worker sorting matches all existing modes, Unicode, unknown artists and ties', () => {
  const items = Array.from({ length: 3000 }, (_, i) => item(i + 1, {
    title: ['原神', 'abc', 'ABC', 'é', 'E'][i % 5],
    simpleTags: i % 7 ? ['artist:' + ['Beta', 'Alpha', '原神'][i % 3]] : []
  }));
  for (const mode of modes) {
    const reference = items.slice(); sortDownloadItems(reference, mode);
    const keys = items.map(i => downloadSortKey(i, mode));
    assert.deepEqual(Object.keys(keys[0]), ['gid', 'value', 'text']);
    assert.deepEqual(sortDownloadKeys(keys, mode), reference.map(i => i.gid), mode);
  }
  assert.deepEqual(items.slice(0, 3).map(i => i.gid), [1, 2, 3]);
});

function createStore() {
  const timers = new Map(); let nextTimer = 0; let snapshots = 0; let membership = 0;
  const state = methods(storeSource, ['subscribe', 'findIndex', 'setProgress', 'setTransfer', 'setStorage', 'notifyChanged',
    'scheduleNotifyChanged', 'emitProgress', 'emitChanged'], {
    setTimeout(fn) { timers.set(++nextTimer, fn); return nextTimer; },
    clearTimeout(id) { timers.delete(id); }, DOWNLOAD_NOTIFY_DEBOUNCE_MS: 50,
    galleryStatusStore: { syncDownloads() { membership++; } }
  });
  Object.assign(state, {
    listeners: [], pendingProgress: new Map(), cachedItemIndexes: new Map(), notifyTimer: -1,
    items: Array.from({ length: 50000 }, (_, i) => item(i + 1)),
    getItems() { snapshots++; return state.items.map(i => ({ ...i })); }, getLabels() { return []; }
  });
  return { state, timers, snapshots: () => snapshots, membership: () => membership,
    flush() { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); } };
}

test('50,000 downloads: progress is batched by GID with zero full snapshots or membership scans', () => {
  const s = createStore(); const batches = []; let fullEvents = 0;
  const unsubscribe = s.state.subscribe(() => { fullEvents++; }, updates => batches.push(updates));
  const initial = s.snapshots();
  for (let i = 1; i <= 1000; i++) {
    s.state.setProgress(25000, i, 2000, i);
    s.state.setTransfer(25000, i * 100, 2000 - i);
  }
  s.state.setStorage(25000, 'local archive', 9000);
  assert.equal(s.timers.size, 1);
  s.flush();
  assert.equal(s.snapshots(), initial);
  assert.equal(s.membership(), 0);
  assert.equal(fullEvents, 1);
  assert.equal(batches.length, 1);
  assert.equal(batches[0].length, 1);
  assert.deepEqual(batches[0][0], { gid: 25000, finished: 1000, total: 2000, downloaded: 1000,
    speed: 100000, remaining: 1000, archiveUri: 'local archive', fileSize: 9000 });
  unsubscribe(); assert.equal(s.state.listeners.length, 0);
});

test('structural events flush pending progress and legacy subscribers retain snapshot behavior', () => {
  const s = createStore(); let batches = 0; let legacy = 0;
  s.state.subscribe(() => {}, () => { batches++; });
  s.state.subscribe(() => { legacy++; });
  s.state.setProgress(1, 1, 3); s.flush();
  assert.equal(legacy, 2); assert.equal(batches, 1);
  s.state.setProgress(1, 2, 3);
  s.state.notifyChanged();
  s.flush();
  assert.equal(legacy, 3); assert.equal(batches, 1);
  assert.equal(s.state.pendingProgress.size, 0);
  assert.equal(s.membership(), 1);
});

const deferred = () => { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; });
  return { promise, resolve, reject }; };
function projection(execute, yieldWork = async () => {}, makeKey = downloadSortKey, timers = {}) {
  const tasks = []; const cancelled = [];
  class Task { constructor(fn, ...args) { Object.assign(this, { fn, args }); tasks.push(this); } }
  const taskpool = { Task, Priority: { LOW: 0 }, execute, cancel(task) { cancelled.push(task); } };
  const source = projectionSource;
  const start = source.indexOf('export class DownloadListProjection');
  const Type = Function('taskpool', 'sortDownloadKeysTask', 'sortDownloadKeys', 'compareDownloadSortKeys',
    'yieldDownloadListWork', 'downloadSortKey', 'setTimeout', 'clearTimeout',
    erase(source.slice(start)) + ';return DownloadListProjection;')(
      taskpool, sortDownloadKeys, sortDownloadKeys, compareDownloadSortKeys, yieldWork, makeKey,
      timers.setTimeout ?? setTimeout, timers.clearTimeout ?? clearTimeout);
  return { instance: new Type(), tasks, cancelled };
}

test('large requests use the worker; small requests stay local and obsolete results cannot publish', async () => {
  const work = deferred(); const p = projection(() => work.promise);
  const keys = Array.from({ length: 50000 }, (_, i) => downloadSortKey(item(i + 1), 'Time desc'));
  const old = p.instance.sort(keys, 'Time desc', p.instance.invalidate());
  const nextRevision = p.instance.invalidate();
  assert.equal(p.cancelled.length, 1);
  const current = await p.instance.sort(keys.slice(0, 3), 'Time asc', nextRevision);
  assert.deepEqual(current, [1, 2, 3]);
  work.resolve([99]); assert.equal(await old, undefined);
  assert.equal(p.tasks.length, 1);
});

test('worker failure uses yielding merge sort, with identical results and interruption support', async () => {
  let yields = 0;
  const p = projection(async () => { throw Error('worker unavailable'); }, async () => { yields++; });
  const keys = Array.from({ length: 20000 }, (_, i) => downloadSortKey(item(i + 1), 'Name desc'));
  const result = await p.instance.sort(keys.slice(), 'Name desc', p.instance.invalidate());
  assert.deepEqual(result, sortDownloadKeys(keys.slice(), 'Name desc'));
  assert.ok(yields > 20);
  const stopped = projection(async () => { throw Error('worker unavailable'); }, async () => {
    stopped.instance.invalidate();
  });
  assert.equal(await stopped.instance.sort(keys, 'Name desc', stopped.instance.invalidate()), undefined);
});

test('search filters before sorting; key cache survives repeated searches and stale preparation stops', async () => {
  let prepares = 0; let chunks = 0;
  const p = projection(async task => task.fn(...task.args), async () => {},
    (i, mode) => { prepares++; return downloadSortKey(i, mode); });
  const state = methods(scene, ['computeVisibleDownloadItems'], {
    yieldDownloadListWork: async () => {},
    filterDownloadItems(items, query, statuses, label, mode, category, sortResults) {
      assert.equal(sortResults, false); assert.ok(items.length <= 256); chunks++; return items;
    },
    galleryMatchesLocalSearch: (i, query) => i.gid % 100 === Number(query)
  });
  Object.assign(state, { items: Array.from({ length: 50000 }, (_, i) => item(i + 1)),
    statusFilters: ['Downloading'], selectedDownloadLabel: '__all__', categoryFilter: 'All', sortMode: 'GID asc',
    query: '0', downloadProjection: p.instance,
    downloadSearchOptions: () => ({}) });
  const result = await state.computeVisibleDownloadItems(p.instance.invalidate());
  assert.equal(result.length, 500); assert.equal(prepares, 500); assert.ok(chunks > 190);
  await state.computeVisibleDownloadItems(p.instance.invalidate()); assert.equal(prepares, 500);
  const revision = p.instance.invalidate(); p.instance.invalidate();
  assert.equal(await state.computeVisibleDownloadItems(revision), undefined);
});

test('progress changes only the affected card; size sorting batches reorder requests', () => {
  const timers = []; let refreshes = 0; const updated = [];
  const p = projection(async task => task.fn(...task.args), async () => {}, downloadSortKey,
    { setTimeout(fn) { timers.push(fn); return timers.length; }, clearTimeout() {} });
  const state = methods(scene, ['updateDownloadProgress'], {
    downloadProgressText: i => String(i.finished), applyDownloadProgressUpdates
  });
  const first = item(1, { fileSize: 10 });
  Object.assign(state, { downloadItemsByGid: new Map([[1, first]]),
    sortMode: 'Name asc',
    downloadCardStateFor: gid => ({ update: (...args) => updated.push([gid, ...args]) }),
    downloadProgressValue: i => i.finished, downloadSpeedLabel: i => String(i.speed),
    downloadProjection: p.instance, refreshDownloadRows() { refreshes++; } });
  const update = { gid: 1, finished: 3, downloaded: 3, total: 100, speed: 20, remaining: 10,
    fileSize: 10, archiveUri: '' };
  state.updateDownloadProgress([update]);
  assert.equal(updated.length, 1); assert.equal(timers.length, 0);
  state.sortMode = 'Size asc';
  state.updateDownloadProgress([{ ...update, fileSize: 20 }]);
  state.updateDownloadProgress([{ ...update, fileSize: 30 }]);
  assert.equal(timers.length, 1); assert.equal(refreshes, 0); assert.equal(p.instance.keys.size, 0);
  timers[0](); assert.equal(refreshes, 1); assert.equal(first.fileSize, 30);
});

test('live size updates do not continually cancel a slow projection; disposal frees pending work and keys', async () => {
  const work = deferred(); const timers = new Map(); let next = 0; let refreshes = 0;
  const p = projection(() => work.promise, async () => {}, downloadSortKey, {
    setTimeout(fn) { timers.set(++next, fn); return next; }, clearTimeout(id) { timers.delete(id); }
  });
  const items = Array.from({ length: 50000 }, (_, i) => item(i + 1));
  const result = p.instance.project(items, 'Size asc', p.instance.invalidate(), chunk => chunk);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(p.tasks.length, 1);
  assert.equal(p.instance.keys.size, 50000);
  for (let i = 0; i < 50; i++) p.instance.scheduleRefresh(() => { refreshes++; });
  assert.equal(timers.size, 1); assert.equal(p.cancelled.length, 0);
  const fire = () => { const [id, fn] = timers.entries().next().value; timers.delete(id); fn(); };
  fire(); assert.equal(refreshes, 0); assert.equal(timers.size, 1);
  work.resolve([1, 2]);
  assert.deepEqual((await result).map(i => i.gid), [1, 2]);
  fire(); assert.equal(refreshes, 1);
  p.instance.scheduleRefresh(() => { refreshes++; });
  p.instance.dispose();
  assert.equal(timers.size, 0); assert.equal(p.instance.keys.size, 0);
});

test('cached GID lookup validates indices when bulk merging shifts entries', () => {
  const s = createStore();
  assert.equal(s.state.findIndex(25000), 24999);
  s.state.items.unshift(item(99999));
  assert.equal(s.state.findIndex(25000), 25000);
  s.state.items.splice(25000, 1);
  assert.equal(s.state.findIndex(25000), -1);
  s.state.notifyChanged();
  assert.equal(s.state.cachedItemIndexes.size, 0);
});

test('production worker dependencies stay UI-free and consumers avoid unnecessary full progress snapshots', () => {
  for (const path of ['services/DownloadSortTask.ets', 'services/DownloadSortKeys.ets']) {
    assert.doesNotMatch(read(path), /EhShared|EhDownloadStore|@State|@Observed|AppStorage/);
  }
  assert.match(read('components/NavigationComponents.ets'), /downloadSummary = downloadQueueSummary\(items\);\s*\}, \(\) => \{\}\)/);
  assert.match(read('services/RemoteStorageSyncService.ets'), /this\.markDirty\(\);\s*\}, \(\) => \{\}\)/);
});

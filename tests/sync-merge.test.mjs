import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const historyStore = read('services/EhHistoryStore.ets');
const downloadStore = read('services/EhDownloadStore.ets');
const syncService = read('services/RemoteStorageSyncService.ets');

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
  return source.slice(start + 1, end - 1);
}

function extractFunction(source, signature) {
  const index = source.indexOf(signature);
  assert.ok(index >= 0, signature);
  const parenStart = source.indexOf('(', index);
  const parenEnd = source.indexOf(')', parenStart);
  const params = source.slice(parenStart + 1, parenEnd)
    .split(',').map((part) => part.trim().split(':')[0].trim()).filter((part) => part.length > 0);
  return Function(...params, block(source, signature));
}

globalThis.HISTORY_SHARD_PREFIX = 'history~';
const historyShardOwner = extractFunction(syncService, 'function historyShardOwner(');
const historyShardIndex = extractFunction(syncService, 'function historyShardIndex(');
globalThis.cloneGalleryInfo = (item) => JSON.parse(JSON.stringify(item));

const importHistoryBackupItems = extractFunction(historyStore, 'importHistoryBackupItems(');
const historyIndexOf = extractFunction(historyStore, 'private indexOf(');
const historyTimeOf = extractFunction(historyStore, 'private historyTimeOf(');

function historyModel(items = []) {
  const state = {
    items,
    saved: 0,
    importHistoryBackupItems,
    indexOf: historyIndexOf,
    historyTimeOf,
    queueSave() { this.saved++; },
    trim(limit) { this.items.splice(limit); },
    sortByTimeDesc() {
      this.items.sort((left, right) => this.historyTimeOf(right) - this.historyTimeOf(left));
    }
  };
  return state;
}

test('newer remote history timestamp wins and untimed remote copies never re-stamp local entries', () => {
  const state = historyModel([{ gid: 1, token: 'a', title: 'local', historyTime: 500 }]);
  state.importHistoryBackupItems([{ gid: 1, token: 'a', title: 'remote', historyTime: 900 }], 100);
  assert.equal(state.items.length, 1);
  assert.equal(state.items[0].title, 'remote');
  assert.equal(state.items[0].historyTime, 900);

  state.importHistoryBackupItems([{ gid: 1, token: 'a', title: 'stale', historyTime: 100 }], 100);
  assert.equal(state.items[0].title, 'remote', 'older remote copy must not overwrite');
  assert.equal(state.items[0].historyTime, 900);

  state.importHistoryBackupItems([{ gid: 1, token: 'a', title: 'untimed' }], 100);
  assert.equal(state.items[0].title, 'remote', 'untimed remote copy must not reset the timestamp');
  assert.equal(state.items[0].historyTime, 900);
});

test('history merge adds remote-only entries below older timestamps and keeps newest-first order', () => {
  const state = historyModel([
    { gid: 1, token: 'a', historyTime: 900 },
    { gid: 2, token: 'b', historyTime: 300 }
  ]);
  const imported = state.importHistoryBackupItems([
    { gid: 3, token: 'c', historyTime: 700 },
    { gid: 4, token: 'd' }
  ], 100);
  assert.equal(imported, 2);
  assert.deepEqual(state.items.map((item) => item.gid), [1, 3, 2, 4]);
  assert.equal(state.items[3].historyTime < 300, true, 'untimed entries go below the oldest timed entry');
});

test('history merge caps to the newest entries and sorts before trimming', () => {
  const state = historyModel([]);
  state.importHistoryBackupItems([
    { gid: 1, token: 'a', historyTime: 100 },
    { gid: 2, token: 'b', historyTime: 300 },
    { gid: 3, token: 'c', historyTime: 200 }
  ], 2);
  assert.deepEqual(state.items.map((item) => item.gid), [2, 3]);
});

test('history item clones keep the browse timestamp for sorting and sync', () => {
  const clone = block(historyStore, 'function cloneGalleryInfo(');
  assert.match(clone, /historyTime: item\.historyTime/, 'cloneGalleryInfo must copy historyTime');
});

test('history shard names are owned per device and legacy numeric shards stay ownerless', () => {
  assert.equal(historyShardOwner('history~device_Pura-X-Max-_HOP-AL10~0'), 'device_Pura-X-Max-_HOP-AL10');
  assert.equal(historyShardOwner('history~0'), '');
  assert.equal(historyShardIndex('history~device_Pura-X-Max-_HOP-AL10~2'), 2);
  assert.equal(historyShardIndex('history~0'), 0);
});

globalThis.DownloadState = {
  Invalid: 'invalid', None: 'none', Wait: 'wait', Downloading: 'downloading',
  Finish: 'finish', Failed: 'failed', Update: 'update'
};
globalThis.cloneDownloadInfo = (item) => JSON.parse(JSON.stringify(item));

const mergeSyncItems = extractFunction(downloadStore, 'mergeSyncItems(');
const getSyncItems = extractFunction(downloadStore, 'getSyncItems(');
const downloadIndexOf = extractFunction(downloadStore, 'private findIndex(');

function downloadModel(items = []) {
  return {
    items,
    notified: 0,
    mergeSyncItems,
    getSyncItems,
    findIndex: downloadIndexOf,
    getItems() { return JSON.parse(JSON.stringify(this.items)); },
    notifyChanged() { this.notified++; }
  };
}

test('downloads merge adds remote entries and keeps local progress for conflicting items', () => {
  const state = downloadModel([
    { gid: 1, token: 'a', title: 'local', state: 'downloading', time: 500, speed: 2048, remaining: 60, archiveUri: 'file://x' }
  ]);
  const changed = state.mergeSyncItems([
    { gid: 1, token: 'a', title: 'remote-newer', state: 'finish', time: 900 },
    { gid: 2, token: 'b', title: 'remote-only', state: 'finish', time: 700 },
    { gid: 3, token: 'c', title: 'remote-active', state: 'downloading', time: 800 }
  ]);
  assert.equal(changed, 3);
  const local = state.items.find((item) => item.gid === 1);
  assert.equal(local.title, 'remote-newer');
  assert.equal(local.time, 900);
  assert.equal(local.state, 'downloading', 'local transfer state must be preserved');
  assert.equal(local.speed, 2048);
  const only = state.items.find((item) => item.gid === 2);
  assert.equal(only.state, 'finish');
  const active = state.items.find((item) => item.gid === 3);
  assert.equal(active.state, 'none', 'remote in-progress entries become idle locally');
  assert.equal(state.notified, 1);
});

test('downloads merge ignores older remote copies and stripped sync items drop transient fields', () => {
  const state = downloadModel([
    { gid: 1, token: 'a', title: 'local', state: 'finish', time: 900, speed: 0, remaining: 0, archiveUri: '' }
  ]);
  const changed = state.mergeSyncItems([{ gid: 1, token: 'a', title: 'stale', state: 'finish', time: 100 }]);
  assert.equal(changed, 0);
  assert.equal(state.items[0].title, 'local');
  state.items[0].speed = 100;
  state.items[0].remaining = 5;
  state.items[0].archiveUri = 'file://local';
  state.items[0].legacy = 1;
  const syncItems = state.getSyncItems();
  assert.equal(syncItems[0].speed, 0);
  assert.equal(syncItems[0].remaining, 0);
  assert.equal(syncItems[0].archiveUri, '');
  assert.equal(syncItems[0].legacy, 0);
});

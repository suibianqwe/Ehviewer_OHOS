import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = name => readFileSync(new URL('../entry/src/main/ets/' + name, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
function erase(source) {
  return source.replace(/^import[\s\S]*?from '[^']+';\n/gm, '').replace(/\b(?:private|export) /g, '')
    .replace(/^interface \w+ \{[\s\S]*?^\}\n/gm, '')
    .replace(/: \([^)]*\) => (?:void|boolean)/g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: (?:Map|Set)<[^>]+>/g, '')
    .replace(/: (?:DownloadManualOrderBackup|DownloadReorderRect|DownloadPageCopy|DownloadInfo|GalleryDownloadUpdateCheck|GalleryDetail|GalleryInfo|GalleryPreview|GalleryPageUrlInfo|GallerySite|EhHttpClient|common.UIAbilityContext|DownloadDirectoryScanResult|UIContext|DragEvent|number|string|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '')
    .replace(/new (?:Map|Set)<[^>]+>/g, match => match.slice(0, match.indexOf('<')));
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function fn(source, name) {
  const start = source.indexOf('function ' + name + '(');
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n}', start) + 2));
}
const parseGalleryPageUrl = Function(fn(read('services/GalleryPageParser.ets'), 'parseGalleryPageUrl') + ';return parseGalleryPageUrl;')();
const reuse = Function('parseGalleryPageUrl', erase(read('services/DownloadPageReuse.ets')) +
  ';return {planDownloadPageReuse,spiderPreviewIdentities,completeDownloadManifest};')(parseGalleryPageUrl);
const hash = value => value.repeat(10);
const preview = (index, token, gid = 1) => ({ index, pageUrl: 'https://e-hentai.org/s/' + hash(token) + '/' + gid + '-' + (index + 1) });
const sourcePreviews = [preview(0, 'a'), preview(1, 'b'), preview(2, 'c')];
const targetPreviews = [preview(0, 'c', 2), preview(1, 'a', 2), preview(2, 'd', 2), preview(3, 'b', 2)];

test('gallery updates reuse image identities across GIDs, reordered pages, insertions and duplicates', () => {
  assert.deepEqual(reuse.planDownloadPageReuse(sourcePreviews, targetPreviews), [
    { sourceIndex: 2, targetIndex: 0 }, { sourceIndex: 0, targetIndex: 1 }, { sourceIndex: 1, targetIndex: 3 }
  ]);
  assert.deepEqual(reuse.planDownloadPageReuse(sourcePreviews, [preview(0, 'a', 9), preview(1, 'a', 9)]), [
    { sourceIndex: 0, targetIndex: 0 }, { sourceIndex: 0, targetIndex: 1 }
  ]);
  const legacy = reuse.spiderPreviewIdentities('VERSION2\n00000000\n1\nabc\n1\n1\n3\n3\n0 AAAAAAAAAA\n1 bbbbbbbbbb\n', 1);
  assert.deepEqual(reuse.planDownloadPageReuse(legacy, [preview(0, 'b', 2), preview(1, 'a', 2)]), [
    { sourceIndex: 1, targetIndex: 0 }, { sourceIndex: 0, targetIndex: 1 }
  ]);
  assert.deepEqual(reuse.planDownloadPageReuse([{ ...preview(0, 'a'), pageUrl: '', imageUrl: 'same-sprite.jpg' }],
    [{ ...preview(0, 'b'), pageUrl: '', imageUrl: 'same-sprite.jpg' }]), []);
  assert.equal(reuse.completeDownloadManifest({ pages: 4, previewSet: targetPreviews }), true);
  assert.equal(reuse.completeDownloadManifest({ pages: 4, previewSet: targetPreviews.slice(0, 3) }), false);
  assert.equal(reuse.completeDownloadManifest({ pages: 0, previewSet: [] }), false);
});

test('reuse copies into new page positions atomically and tolerates missing/cancelled old pages', async () => {
  const files = new Map([['/old/00000001.JPG', 'A'], ['/old/00000002.webp', 'B'], ['/old/00000003.png', 'C']]);
  const events = [];
  const fs = {
    async listFile(dir) { return [...files.keys()].filter(p => p.startsWith(dir + '/')).map(p => p.slice(dir.length + 1)); },
    async stat(path) { return { size: files.get(path)?.length ?? 0 }; },
    async copyFile(from, to) { assert.ok(to.endsWith('.reuse')); events.push(from); files.set(to, files.get(from)); },
    async rename(from, to) { files.set(to, files.get(from)); files.delete(from); },
    async unlink(path) { files.delete(path); }
  };
  const model = Function('fs', 'planDownloadPageReuse', 'pageFileName', 'return {' +
    method(read('services/EhDownloadFileStore.ets'), 'reuseGalleryPages') + '};')(
      fs, reuse.planDownloadPageReuse, (i, ext) => String(i + 1).padStart(8, '0') + ext);
  assert.equal(await model.reuseGalleryPages('/old', sourcePreviews, '/new', targetPreviews, () => false), 3);
  assert.equal(files.get('/new/00000001.png'), 'C');
  assert.equal(files.get('/new/00000002.jpg'), 'A');
  assert.equal(files.get('/new/00000004.webp'), 'B');
  assert.equal(files.has('/new/00000003.webp'), false);
  assert.equal(files.get('/old/00000001.JPG'), 'A');
  assert.equal(await model.reuseGalleryPages('/old', sourcePreviews, '/new', targetPreviews, () => false), 0);
  assert.equal(await model.reuseGalleryPages('/old', sourcePreviews, '/cancelled', targetPreviews, () => true), 0);
  assert.equal(events.length, 3);
});

const manual = Function(erase(read('services/DownloadManualOrder.ets')) +
  ';return {completeDownloadManualOrder,normalizeDownloadOrderBackup,newerDownloadOrder};')();
function store() {
  const source = read('services/EhDownloadStore.ets');
  const deleted = [];
  const names = ['findIndex', 'contains', 'getItem', 'getGalleryIds', 'getUpdatingGalleryIds', 'getSyncItems', 'getManualOrder', 'getManualOrderBackup', 'manualOrderRevision',
    'mergeManualOrderBackup', 'commitVisibleManualOrder', 'queueGalleryUpdate', 'completeGalleryUpdate', 'restoreGalleryUpdate', 'updateGallery'];
  const model = Function('cloneDownloadInfo', 'galleryToDownloadInfo', 'completeDownloadManualOrder',
    'normalizeDownloadOrderBackup', 'newerDownloadOrder', 'DownloadState', 'syncTombstoneStore', 'SYNC_SECTION_DOWNLOADS',
    'return {' + names.map(n => method(source, n)).join(',') + '};')(
      x => ({ ...x }), (gallery, label) => ({ ...gallery, label, state: 'none' }), manual.completeDownloadManualOrder,
      manual.normalizeDownloadOrderBackup, manual.newerDownloadOrder,
      { Finish: 'finish', Wait: 'wait', Downloading: 'downloading' },
      { recordDeletion(...args) { deleted.push(args); } }, 'downloads');
  Object.assign(model, { items: [], manualOrder: [], manualOrderTime: 0, context: {}, cachedItemIndexes: new Map(),
    getItems() { return model.items.map(item => ({ ...item })); },
    notifyChanged() { model.cachedItemIndexes.clear(); } });
  return { model, deleted };
}

test('WebDAV manual order converges by edit time, retains unknown IDs and rejects stale/corrupt state', () => {
  const a = store().model; a.items = [1, 2, 3].map(gid => ({ gid }));
  assert.equal(a.mergeManualOrderBackup({ updatedAt: 10, gids: [3, 99, 2, 1] }), true);
  assert.deepEqual(a.getManualOrder(), [3, 2, 1]);
  assert.deepEqual(a.getManualOrderBackup().gids, [3, 99, 2, 1]);
  assert.equal(a.mergeManualOrderBackup({ updatedAt: 9, gids: [1, 2, 3] }), false);
  assert.equal(a.mergeManualOrderBackup({ updatedAt: 0, gids: [] }), false);
  assert.equal(a.mergeManualOrderBackup(null), false);
  const left = { updatedAt: 11, gids: [1, 2, 3] }, right = { updatedAt: 11, gids: [3, 2, 1] };
  assert.equal(manual.newerDownloadOrder(left, right), true);
  assert.equal(manual.newerDownloadOrder(right, left), false);
  a.items.push({ gid: 99 });
  assert.deepEqual(a.getManualOrder(), [3, 99, 2, 1]);
  const sync = read('services/RemoteStorageSyncService.ets');
  assert.match(sync, /sectionFromPayload\(SYNC_SECTION_DOWNLOAD_ORDER, ehDownloadStore.getManualOrderBackup\(\)\)/);
  assert.match(sync, /name === SYNC_SECTION_DOWNLOAD_ORDER[\s\S]*?mergeManualOrderBackup/);
  assert.match(sync, /downloadStoreSignature\(items\) \+ '\|order:' \+ ehDownloadStore.manualOrderRevision/);
});

test('filtered drag commits only visible slots while timestamps, hidden items and queue stay intact', () => {
  const a = store().model;
  a.items = [1, 2, 3, 4].map(gid => ({ gid, time: gid * 10, finished: gid }));
  const before = structuredClone(a.items);
  assert.equal(a.commitVisibleManualOrder([3, 1]), true);
  assert.deepEqual(a.getManualOrder(), [3, 2, 1, 4]);
  assert.ok(a.manualOrderRevision() > 0);
  assert.deepEqual(a.items, before);
  assert.equal(a.commitVisibleManualOrder([3, 3]), false);
  assert.equal(a.commitVisibleManualOrder([99, 1]), false);
});

test('gallery replacement retains the old copy until completion and carries label, date and manual slot', () => {
  const { model: a, deleted } = store();
  a.items = [{ gid: 1, token: 'aaa', state: 'finish', time: 123, label: 'Books', archiveUri: '/old' }, { gid: 7 }];
  a.manualOrder = [7, 1];
  const queued = a.queueGalleryUpdate(1, { gid: 2, token: 'bbb', pages: 4 });
  assert.equal(queued.label, 'Books'); assert.equal(queued.time, 123); assert.equal(queued.updateSourceGid, 1);
  assert.equal(a.getItem(1).state, 'finish');
  assert.equal(a.completeGalleryUpdate(2), null);
  a.updateGallery({ gid: 2, token: 'bbb', pages: 4 });
  assert.equal(a.getItem(2).updateSourceGid, 1, 'detail refresh cannot erase the durable update task');
  a.items.find(i => i.gid === 2).state = 'failed';
  assert.equal(a.completeGalleryUpdate(2), null);
  assert.ok(a.getItem(1));
  a.items.find(i => i.gid === 2).state = 'finish';
  const replaced = a.completeGalleryUpdate(2);
  assert.equal(replaced.gid, 1);
  assert.equal(a.getItem(1), null);
  assert.deepEqual(a.getManualOrder(), [7, 2]);
  assert.equal(deleted.length, 0, 'the tombstone is recorded by the manager only after persistence succeeds');
  a.restoreGalleryUpdate(replaced, 2);
  assert.equal(a.getItem(1).archiveUri, '/old');
  assert.equal(a.getItem(2).updateSourceGid, 1);
  assert.deepEqual(a.getManualOrder(), [7, 1, 2]);
});

test('repeat update requests reuse one task and WebDAV publishes only the complete version', () => {
  const a = store().model;
  a.items = [{ gid: 1, token: 'aaa', state: 'finish', time: 123, label: 'Books' }];
  assert.equal(a.queueGalleryUpdate(1, { gid: 2, token: 'bbb' }).gid, 2);
  a.items.find(i => i.gid === 2).state = 'failed';
  assert.equal(a.queueGalleryUpdate(1, { gid: 3, token: 'ccc' }).gid, 2);
  assert.equal(a.getItem(2).state, 'wait');
  assert.equal(a.items.length, 2);
  assert.deepEqual(a.getUpdatingGalleryIds(), [2]);
  assert.deepEqual(a.getSyncItems().map(i => i.gid), [1]);
  assert.equal(a.getItem(2).updateSourceGid, 1, 'sync sanitization must not alter the durable local task');
  a.items.find(i => i.gid === 2).state = 'finish';
  a.completeGalleryUpdate(2);
  assert.deepEqual(a.getUpdatingGalleryIds(), []);
  assert.deepEqual(a.getSyncItems().map(i => i.gid), [2]);
  assert.match(read('services/RemoteStorageSyncService.ets'), /updatingGids.has\(Number.parseInt\(galleryName, 10\)\)/);
});

test('update button checks the server afresh and follows the newest gallery chain before queuing', async () => {
  const check = Function(erase(read('services/GalleryDownloadUpdate.ets')) + ';return checkGalleryDownloadUpdate;')();
  const calls = [];
  const galleries = new Map([
    [1, { gid: 1, token: 'aaa', newerVersions: [{ gid: 2, token: 'bbb' }] }],
    [2, { gid: 2, token: 'bbb', newerVersions: [{ gid: 3, token: 'ccc' }] }],
    [3, { gid: 3, token: 'ccc', newerVersions: [] }]
  ]);
  const client = { async loadGalleryDetail(...args) { calls.push(args); return { ok: true, detail: galleries.get(args[0]) }; } };
  const result = await check(client, 1, 'aaa', 0, 'referer');
  assert.equal(result.latest.gid, 3);
  assert.ok(calls.every(args => args[5] === true));
  assert.equal((await check(client, 3, 'ccc', 0, '')).latest, null);
  galleries.get(3).newerVersions.push({ gid: 1, token: 'aaa' });
  await assert.rejects(check(client, 1, 'aaa', 0, ''), /Invalid gallery version chain/);
  const header = read('components/detail/DetailHeader.ets');
  assert.match(header, /this.downloadText === 'Update'[\s\S]*?sys.symbol.trash/);
  assert.doesNotMatch(read('components/detail/DetailInfo.ets'), /Newer version/);
  const source = read('services/GalleryDetailSupport.ets');
  const label = Function('findDetailDownloadItem', 'DownloadState', 'isDetailCloudOnlyDownload', 'downloadStateLabel',
    fn(source, 'detailDownloadButtonText') + ';return detailDownloadButtonText;')(
      () => ({ state: 'finish' }), { Finish: 'finish' }, () => true, x => x);
  assert.equal(label(1, true), 'Update');
  assert.equal(label(1, false), 'Delete');
});

test('waterfall insertion uses actual spatial slots and previews animate before the drop', () => {
  const nearest = Function(fn(read('services/DownloadReorderController.ets'), 'nearestDownloadSlot') + ';return nearestDownloadSlot;')();
  assert.equal(nearest([{ gid: 1, x: 0, y: 0 }, { gid: 2, x: 100, y: 0 }, { gid: 3, x: 100, y: 110 }], 100, 112), 3);
  const animations = [];
  let items = [{ gid: 1 }, { gid: 2 }, { gid: 3 }];
  const initial = items.slice();
  const context = { px2vp: x => x / 2, animateTo(config, change) { animations.push(config); change(); },
    getComponentUtils: () => ({ getRectangleById(id) {
      if (id.endsWith('viewport')) return { windowOffset: { x: 0, y: 0 }, size: { width: 400, height: 2000 } };
      const index = items.findIndex(i => id === 'download-reorder-' + i.gid);
      return { windowOffset: { x: index % 2 * 200, y: Math.floor(index / 2) * 400 }, size: { width: 200, height: 400 } };
    } }) };
  const DragResult = { DRAG_FAILED: 1, DRAG_SUCCESSFUL: 0 };
  const Type = Function('nearestDownloadSlot', 'curves', 'DragResult',
    erase(read('services/DownloadReorderController.ets').slice(read('services/DownloadReorderController.ets').indexOf('export class'))) +
    ';return DownloadReorderController;')(nearest, { interpolatingSpring: () => 'spring' }, DragResult);
  const controller = new Type();
  const event = (x, y) => ({ getWindowX: () => x, getWindowY: () => y, setResult(result) { this.result = result; } });
  [1, 2, 3].forEach(gid => controller.markVisible(gid, true));
  controller.start(items, 1, event(50, 50), context, next => { items = next; }, () => {});
  controller.move(event(150, 50));
  assert.deepEqual(items.map(i => i.gid), [2, 1, 3], 'other cards change position while the finger is still down');
  assert.equal(animations[0].duration, 180);
  assert.deepEqual(controller.finish(event(150, 50)), [2, 1, 3]);
  controller.cancel();
  assert.deepEqual(items.map(i => i.gid), [2, 1, 3], 'drag-end after drop cannot roll back a committed preview');
  items = initial.slice();
  controller.start(items, 1, event(50, 50), context, next => { items = next; }, () => {});
  controller.move(event(150, 50));
  controller.cancel();
  assert.deepEqual(items, initial, 'cancel restores the original permutation');
});

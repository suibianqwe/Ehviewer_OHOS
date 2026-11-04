import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
function erase(source) {
  return source.replace(/^import .*;\n/gm, '').replace(/\b(?:export|private) /g, '')
    .replace(/^interface \w+ \{[\s\S]*?^\}\n/gm, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: Set<[^>]+>/g, '')
    .replace(/: (?:DownloadManualOrderBackup|GalleryVersion|GalleryDetailParseResult|GalleryCategory|GalleryDetail|GalleryInfo|GalleryComment|GalleryPreview|GalleryTagGroup|GalleryTagInfo|CommentAnchor|StyleOffset|RegExpExecArray|RegExp|DownloadInfo|DetailDownloadToggleResult|string|number|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '')
    .replace(/new Set<(?:number|string)>/g, 'new Set');
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
const { completeDownloadManualOrder, moveDownloadInOrder } = Function(
  erase(read('services/DownloadManualOrder.ets')) + '; return { completeDownloadManualOrder, moveDownloadInOrder };')();

test('manual order loads old data, removes stale/duplicate IDs and retains new downloads', () => {
  assert.deepEqual(completeDownloadManualOrder([], [3, 1, 2]), [3, 1, 2]);
  assert.deepEqual(completeDownloadManualOrder([2, 99, 2, 1], [3, 1, 2, 4]), [2, 1, 3, 4]);
  const ids = Array.from({ length: 50000 }, (_, i) => i + 1);
  assert.deepEqual(completeDownloadManualOrder(ids.toReversed(), ids), ids.toReversed());
});

test('moving filtered downloads retains hidden entries and leaves the queue, dates and progress intact', () => {
  const source = read('services/EhDownloadStore.ets');
  const state = Function('completeDownloadManualOrder', 'moveDownloadInOrder', 'return {' +
    ['getGalleryIds', 'getManualOrder', 'seedManualOrder', 'moveInManualOrder'].map(n => method(source, n)).join(',') + '};')(
      completeDownloadManualOrder, moveDownloadInOrder);
  let changed = 0;
  Object.assign(state, { items: [1, 2, 3, 4].map(gid => ({ gid, time: gid * 10, finished: gid })),
    manualOrder: [], manualOrderTime: 0, notifyChanged() { changed++; } });
  const before = structuredClone(state.items);
  state.seedManualOrder([1, 2, 3, 4]);
  assert.equal(state.moveInManualOrder(1, 3), true);
  assert.deepEqual(state.getManualOrder(), [2, 3, 1, 4]);
  assert.equal(state.moveInManualOrder(1, 3), true);
  assert.deepEqual(state.getManualOrder(), [2, 1, 3, 4]);
  assert.equal(state.moveInManualOrder(99, 3), false);
  assert.equal(state.moveInManualOrder(3, 3), false);
  assert.equal(changed, 2);
  assert.deepEqual(state.items, before);
  assert.match(source, /prefs\.get\(MANUAL_ORDER_KEY, '\[\]'/);
  assert.match(source, /prefs\.put\(MANUAL_ORDER_KEY, manualOrder\)/);
});

test('both download card layouts hand cover and selection gestures to native sorting only while enabled', () => {
  const cards = read('components/GalleryCards.ets');
  const scene = read('components/DownloadScene.ets');
  assert.equal((cards.match(/imageDraggable: !this\.dragSortEnabled/g) ?? []).length, 2);
  assert.match(cards, /Image\(this\.thumbnailSource\)\s*\.draggable\(this\.imageDraggable\)/);
  assert.equal((cards.match(/this\.dragSortEnabled && info\.tag === 'gallery-selection'/g) ?? []).length, 2);
  assert.match(scene, /\.draggable\(this\.dragSortEnabled\)[\s\S]*?\.onDragStart[\s\S]*?\.onDrop/);
});

const decodeHtmlEntities = Function(erase(read('shared/HtmlEntitySupport.ets')) + '; return decodeHtmlEntities;')();
const parseDetailRated = Function(erase(read('services/GalleryRatingSupport.ets')) + '; return parseDetailRated;')();
const parseGalleryDetail = Function('decodeHtmlEntities', 'parseDetailRated', 'GalleryCategory',
  erase(read('services/GalleryDetailParser.ets')) + '; return parseGalleryDetail;')(
    decodeHtmlEntities, parseDetailRated, { Unknown: 0 });
const html = notice => '<script>var gid = 1; var token = "abc"; var apiuid = 2; var apikey = "def";</script>' + notice;

test('new versions come only from the site notice and survive detail cloning', () => {
  const parsed = parseGalleryDetail(html(`<div id="gnd">Newer versions
    <a href="https://e-hentai.org/g/2/abc/?a=1&amp;b=2">Version &amp; two</a><br />
    <a href="/g/3/def/">Version three</a><a href="/g/2/abc/">Duplicate</a>
    <a href="https://exhentai.org/g/4/fff/">Version four</a>
    <a href="/g/1/abc/">Self</a><a href="https://example.com/g/5/abc/">External</a>
    </div><div id="comments"><a href="/g/6/abc/">Comment</a></div>`)).detail;
  assert.deepEqual(parsed.newerVersions.map(v => v.gid), [2, 3, 4]);
  assert.equal(parsed.newerVersions[0].title, 'Version & two');
  assert.equal(parsed.newerVersions[0].url, 'https://e-hentai.org/g/2/abc/?a=1&b=2');
  assert.deepEqual(parseGalleryDetail(html('<div data-id="gnd"><a href="/g/2/abc/">False notice</a></div>'))
    .detail.newerVersions, []);
  assert.deepEqual(parseGalleryDetail(html('<a href="/g/2/abc/">Ordinary link</a>')).detail.newerVersions, []);
  const clone = Function('cloneGalleryInfo', 'cloneGalleryTagGroups', 'cloneGalleryComments', 'cloneGalleryPreviews',
    fn(read('shared/EhShared.ets'), 'cloneGalleryDetail') + ';return cloneGalleryDetail;')(
      x => ({ ...x }), x => x ?? [], x => x ?? [], x => x ?? []);
  const copied = clone(parsed);
  copied.newerVersions[0].title = 'Changed';
  assert.equal(parsed.newerVersions[0].title, 'Version & two');
  assert.deepEqual(clone({ ...parsed, newerVersions: undefined }).newerVersions, []);
});

test('completed download cannot be queued again through the shared detail action', () => {
  const calls = [];
  const current = { gid: 1, token: 'abc', state: 'finish' };
  const toggle = Function('findDetailDownloadItem', 'DownloadState', 'detailDownloadButtonText',
    'ehDownloadStore', 'ehDownloadManager', 'saveDownloadsQuietly',
    fn(read('services/GalleryDetailSupport.ets'), 'toggleDetailDownloadTask') + ';return toggleDetailDownloadTask;')(
      () => current, { Finish: 'finish', Wait: 'wait', Downloading: 'downloading' }, () => 'Downloaded',
      { updateGallery() { calls.push('update'); } }, { resumeGallery() { calls.push('resume'); } },
      () => calls.push('save'));
  assert.equal(toggle(current).shouldStartQueue, false);
  assert.deepEqual(calls, []);
});

test('download deletion requires confirmation, handles cancellation, and keeps cloud metadata', async () => {
  const code = read('components/GalleryDetailHostScene.ets');
  const calls = [];
  const current = { gid: 1, state: 'finish' };
  let result = { index: 0 };
  let cloud = false;
  const model = Function('getAbilityContext', 'uiText', 'themeSecondaryText', 'themeAccentTextColor',
    'findDetailDownloadItem', 'DownloadState', 'ehDownloadManager', 'ehDownloadFileStore',
    'cloudGalleryPageService', 'ehDownloadStore', 'isDetailCloudOnlyDownload', 'remoteStorageDownloadDeletionService',
    'return {' + method(code, 'confirmDeleteDownloadedGallery') + '};')(
      () => ({}), x => x, () => '', () => '', () => current, { Finish: 'finish' },
      { stopGallery() { calls.push('stop'); } }, { async removeGalleryDirectoryAsync() { calls.push('files'); } },
      { hasDownloadsProfile: () => cloud }, { removeGallery() { calls.push('remove'); }, async save() { calls.push('save'); } },
      () => false, {});
  Object.assign(model, { deleteDownloadDialogOpen: false, detail: { gid: 1 },
    getUIContext: () => ({ getPromptAction: () => ({ showDialog: async () => result }) }),
    refreshDetailDownloadText() { calls.push('refresh'); }, showToast() { calls.push('error'); } });
  const flush = () => new Promise(resolve => setImmediate(resolve));
  model.confirmDeleteDownloadedGallery(current); await flush();
  assert.deepEqual(calls, []);
  result = { index: 1 };
  model.confirmDeleteDownloadedGallery(current); await flush();
  assert.deepEqual(calls.splice(0), ['stop', 'files', 'remove', 'save', 'refresh']);
  cloud = true;
  model.confirmDeleteDownloadedGallery(current); await flush();
  assert.deepEqual(calls.splice(0), ['stop', 'files', 'save', 'refresh']);
  model.getUIContext = () => ({ getPromptAction: () => ({ showDialog: async () => { throw Error('dismissed'); } }) });
  model.confirmDeleteDownloadedGallery(current); await flush();
  assert.deepEqual(calls, []);
  assert.equal(model.deleteDownloadDialogOpen, false);
  assert.match(code, /current\.state === DownloadState.Finish[\s\S]*?this\.confirmDeleteDownloadedGallery\(current\)/);
});

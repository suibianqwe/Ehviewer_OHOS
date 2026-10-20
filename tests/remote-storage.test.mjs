import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

// Only erase the types used by these pure functions, not their implementation.
function executable(source) {
  return source.replace(/^import[\s\S]*?from '[^']+';\r?\n/gm, '')
    .replace(/: Promise<string>/g, '')
    .replace(/\bexport /g, '')
    .replace(/\b(private|readonly|protected|public) /g, '')
    .replace(/interface \w+ \{[^}]*\}/g, '')
    .replace(/ as (?:RemoteStorageProfile\[\] \| null|RemoteStorageProfile\[\]|RemoteStorageProfile)/g, '')
    .replace(/: (?:common\.UIAbilityContext \| null|common\.UIAbilityContext|Promise<void> \| null|Promise<RemoteStorageProfile \| null>|Promise<RemoteStorageProfile\[\]>|Promise<boolean>|Promise<void>|RemoteStorageProfile \| null|RemoteStorageProfile\[\]|RemoteStorageProfile|RemoteStorageListEntry \| null|RemoteStorageListEntry\[\]|RemoteStorageListEntry|RegExpExecArray \| null|RegExp|string\[\]|string|number|boolean|void)(?:\[\])?/g, '')
    .replace(/AppStorage\.(get|setOrCreate)<number>/g, 'AppStorage.$1');
}

const supportSource = executable(read('entry/src/main/ets/services/RemoteStorageSupport.ets'))
  .replace(/new Map<[^>]+>\(\)/g, 'new Map()')
  .replace(/: Map<[^>]+>/g, '')
  .replace(/: SyncTombstoneLike\[\]/g, '')
  .replace(/: SyncTombstoneLike/g, '')
  .replace(/: number\[\]/g, '')
  .replace(/: string\[\]/g, '');

const support = Function(supportSource +
  '\nreturn { normalizeRemoteStorageUrl, normalizeRemoteStorageBasePath, remoteStorageJoinPath,' +
  ' remoteStorageUrlForPath, remoteStorageRelativePathFromHref, decodeWebDavXmlEntities,' +
  ' webDavStatusMessage, parseWebDavMultiStatus, createRemoteStorageProfileId, isValidRemoteStorageUrl,' +
  ' remoteStorageHost, normalizeRemoteStoragePort, remoteStoragePortFromUrl, remoteStorageUrlWithoutPort,' +
  ' remoteStorageApplyPort, resolveRedirectUrl, isRedirectStatus };')();

const profileFactory = Function('createRemoteStorageProfileId', 'isValidRemoteStorageUrl', 'normalizeRemoteStorageBasePath',
  'normalizeRemoteStorageUrl', 'remoteStorageHost', 'normalizeRemoteStoragePort', 'remoteStorageApplyPort',
  'remoteStoragePortFromUrl', 'preferences', 'syncTombstoneStore', 'AppStorage',
  executable(read('entry/src/main/ets/services/RemoteStorageProfiles.ets')) +
  '\nreturn { parseRemoteStorageProfiles, normalizeRemoteStorageProfile, remoteStorageProfileForPurpose,' +
  ' remoteStorageProfileSummary, RemoteStorageProfileStore };');
const supportArgs = [support.createRemoteStorageProfileId, support.isValidRemoteStorageUrl,
  support.normalizeRemoteStorageBasePath, support.normalizeRemoteStorageUrl, support.remoteStorageHost,
  support.normalizeRemoteStoragePort, support.remoteStorageApplyPort, support.remoteStoragePortFromUrl];
const profiles = profileFactory(...supportArgs);

test('remote storage paths normalize and join for WebDAV URLs', () => {
  assert.equal(support.normalizeRemoteStorageUrl('dav.example.com/dav/'), 'http://dav.example.com/dav');
  assert.equal(support.normalizeRemoteStorageUrl('http://host/dav//'), 'http://host/dav');
  assert.equal(support.normalizeRemoteStorageUrl('  '), '');
  assert.equal(support.normalizeRemoteStorageBasePath('/eh\\viewer// data/'), 'eh/viewer/data');
  assert.equal(support.normalizeRemoteStorageBasePath('../'), '');
  assert.equal(support.remoteStorageJoinPath('a/b', 'c//d/'), 'a/b/c/d');
  assert.equal(support.remoteStorageUrlForPath('https://host/dav/', 'backup/a.json'),
    'https://host/dav/backup/a.json');
  assert.equal(support.remoteStorageUrlForPath('http://host:5005', 'download/中文 目录/a b.jpg'),
    'http://host:5005/download/' + encodeURIComponent('中文 目录') + '/' + encodeURIComponent('a b.jpg'));
  assert.equal(support.isValidRemoteStorageUrl('https://host/dav'), true);
  assert.equal(support.isValidRemoteStorageUrl('not a url'), false);
});

test('remote storage ports can be supplied separately from the URL', () => {
  assert.equal(support.normalizeRemoteStoragePort('8443'), '8443');
  assert.equal(support.normalizeRemoteStoragePort('0'), '');
  assert.equal(support.normalizeRemoteStoragePort('70000'), '');
  assert.equal(support.normalizeRemoteStoragePort('abc'), '');
  assert.equal(support.remoteStoragePortFromUrl('https://host:1234/dav'), '1234');
  assert.equal(support.remoteStoragePortFromUrl('https://host/dav'), '');
  assert.equal(support.remoteStorageUrlWithoutPort('https://host:1234/dav'), 'https://host/dav');
  assert.equal(support.remoteStorageUrlWithoutPort('https://host/dav'), 'https://host/dav');
  assert.equal(support.remoteStorageApplyPort('https://host/dav', '8443'), 'https://host:8443/dav');
  assert.equal(support.remoteStorageApplyPort('https://host:1234/dav', '8443'), 'https://host:8443/dav');
  assert.equal(support.remoteStorageApplyPort('https://host:1234/dav', ''), 'https://host:1234/dav');
});

test('WebDAV hrefs resolve relative to the configured base folder', () => {
  assert.equal(support.remoteStorageRelativePathFromHref('https://host/dav/ehviewer/backup/a.json', 'ehviewer'),
    'backup/a.json');
  assert.equal(support.remoteStorageRelativePathFromHref('/dav/ehviewer/', 'ehviewer'), '');
  assert.equal(support.remoteStorageRelativePathFromHref('/dav/ehviewer/backup/', '/ehviewer/'), 'backup');
  assert.equal(support.remoteStorageRelativePathFromHref('/dav/other/a.json', 'ehviewer'), '');
  assert.equal(support.remoteStorageRelativePathFromHref('/dav/ehviewer/a%20b.json', 'ehviewer'), 'a b.json');
});

test('WebDAV multistatus parsing keeps names, folders, size and time', () => {
  const xml = '<?xml version="1.0"?>' +
    '<d:multistatus xmlns:d="DAV:">' +
    '<d:response><d:href>/dav/ehviewer/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/>' +
    '</d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>' +
    '<d:response><d:href>/dav/ehviewer/backup/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/>' +
    '</d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>' +
    '<d:response><d:href>/dav/ehviewer/backup/ehviewer_%26backup.json</d:href><d:propstat><d:prop>' +
    '<d:resourcetype/><d:getcontentlength>4096</d:getcontentlength>' +
    '<d:getlastmodified>Wed, 10 Sep 2026 12:00:00 GMT</d:getlastmodified></d:prop>' +
    '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>' +
    '</d:multistatus>';
  const entries = support.parseWebDavMultiStatus(xml, 'ehviewer');
  assert.equal(entries.length, 2);
  assert.equal(entries[0].name, 'backup');
  assert.equal(entries[0].isDirectory, true);
  assert.equal(entries[1].name, 'ehviewer_&backup.json');
  assert.equal(entries[1].isDirectory, false);
  assert.equal(entries[1].size, 4096);
  assert.ok(entries[1].modifiedAt > 0);
  assert.equal(support.decodeWebDavXmlEntities('a&amp;b&lt;c&gt;&quot;d&quot;'), 'a&b<c>"d"');
});

test('WebDAV status messages cover authentication and protocol failures', () => {
  assert.equal(support.webDavStatusMessage(401), 'Authentication failed');
  assert.equal(support.webDavStatusMessage(404), 'Remote path not found');
  assert.match(support.webDavStatusMessage(405), /not supported/);
  assert.equal(support.webDavStatusMessage(200), '');
});

test('remote storage profiles parse defensively and resolve by purpose', () => {
  const raw = JSON.stringify([
    {
      id: 'p1', name: 'NAS', kind: 'webdav', url: 'dav.example.com/dav/', port: '8443',
      username: 'u', password: 'p', basePath: '/ehviewer/backup/', useForBackup: true,
      useForSync: false, useForDownloads: true, updatedAt: 5
    },
    { id: 'broken', url: '' },
    'noise'
  ]);
  const parsed = profiles.parseRemoteStorageProfiles(raw);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].url, 'http://dav.example.com/dav');
  assert.equal(parsed[0].basePath, 'ehviewer/backup');
  assert.equal(parsed[0].port, '8443');
  assert.equal(parsed[0].updatedAt, 5);
  assert.equal(profiles.parseRemoteStorageProfiles('not json').length, 0);
  const backupProfile = profiles.remoteStorageProfileForPurpose(parsed, 'backup');
  assert.ok(backupProfile !== null);
  assert.equal(backupProfile.id, 'p1');
  assert.equal(profiles.remoteStorageProfileForPurpose(parsed, 'sync'), null);
  assert.equal(profiles.remoteStorageProfileSummary(parsed[0]), 'dav.example.com:8443 · ehviewer/backup');
});

const tombstones = Function(supportSource +
  '\nreturn { mergeSyncTombstoneLists, syncTombstoneShouldDelete, pruneSyncTombstoneList,' +
  ' filterTombstoneKey, keywordTombstoneKey };')();

test('sync tombstones keep the newest operation per key', () => {
  const merged = tombstones.mergeSyncTombstoneLists(
    [{ key: 'a', deletedAt: 10 }, { key: 'b', deletedAt: 30 }],
    [{ key: 'a', deletedAt: 20 }, { key: 'c', deletedAt: 5 }, { key: '', deletedAt: 99 }]);
  assert.deepEqual(merged, [
    { key: 'c', deletedAt: 5 },
    { key: 'a', deletedAt: 20 },
    { key: 'b', deletedAt: 30 }
  ]);
  const clearedWins = tombstones.mergeSyncTombstoneLists(
    [{ key: 'a', deletedAt: 30 }], [{ key: 'a', deletedAt: 40, cleared: true }]);
  assert.equal(clearedWins[0].cleared, true);
  const deletionWins = tombstones.mergeSyncTombstoneLists(
    [{ key: 'a', deletedAt: 50, cleared: true }], [{ key: 'a', deletedAt: 60 }]);
  assert.equal(deletionWins[0].cleared, undefined);
});

test('sync tombstone deletion respects item timestamps and clears', () => {
  assert.equal(tombstones.syncTombstoneShouldDelete({ key: 'a', deletedAt: 100 }, 50), true);
  assert.equal(tombstones.syncTombstoneShouldDelete({ key: 'a', deletedAt: 100 }, 150), false);
  assert.equal(tombstones.syncTombstoneShouldDelete({ key: 'a', deletedAt: 100 }, 0), true);
  assert.equal(tombstones.syncTombstoneShouldDelete({ key: 'a', deletedAt: 100, cleared: true }, 0), false);
});

test('sync tombstones prune by age and normalize keys', () => {
  const now = 2000;
  const kept = tombstones.pruneSyncTombstoneList(
    [{ key: 'old', deletedAt: 0 }, { key: 'new', deletedAt: 1900 }, { key: 'clear', deletedAt: 1950, cleared: true }],
    now, 500);
  assert.deepEqual(kept.map((record) => record.key), ['new', 'clear']);
  assert.equal(tombstones.filterTombstoneKey(2, '  Title Tag '), '2|title tag');
  assert.equal(tombstones.keywordTombstoneKey('  Hello World '), 'hello world');
});

test('webdav redirects resolve absolute, protocol-relative and relative targets', () => {
  assert.equal(support.isRedirectStatus(301), true);
  assert.equal(support.isRedirectStatus(308), true);
  assert.equal(support.isRedirectStatus(303), true);
  assert.equal(support.isRedirectStatus(200), false);
  assert.equal(support.isRedirectStatus(401), false);
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json', 'https://host/dav/a.json'),
    'https://host/dav/a.json');
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json', '//host/dav/a.json'),
    'http://host/dav/a.json');
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json', '/dav/b.json'),
    'http://host:5005/dav/b.json');
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json', 'b.json'),
    'http://host:5005/dav/b.json');
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json?x=1#frag', 'b.json'),
    'http://host:5005/dav/b.json');
  assert.equal(support.resolveRedirectUrl('http://host:5005/dav/a.json', '   '), '');
});

test('https profiles default to port 5006 and keep explicit ports', () => {
  const base = {
    id: 'p1', name: '', kind: 'webdav', url: 'https://host/dav', port: '', username: '', password: '',
    basePath: '', useForBackup: true, useForSync: false, useForDownloads: false, ignoreCertificate: false,
    updatedAt: 1
  };
  const normalized = profiles.normalizeRemoteStorageProfile(base);
  assert.equal(normalized.port, '5006');
  assert.equal(normalized.ignoreCertificate, false);
  const explicit = profiles.normalizeRemoteStorageProfile(Object.assign({}, base, { url: 'https://host:8443/dav' }));
  assert.equal(explicit.port, '');
  const plainHttp = profiles.normalizeRemoteStorageProfile(Object.assign({}, base, { url: 'http://host/dav' }));
  assert.equal(plainHttp.port, '');
  const ignored = profiles.normalizeRemoteStorageProfile(Object.assign({}, base, { ignoreCertificate: true }));
  assert.equal(ignored.ignoreCertificate, true);
});

const fixture = (fields = {}) => ({ id: 'fixture', name: 'Before', kind: 'webdav', url: 'https://example.invalid/dav',
  port: '8443', username: 'synthetic', password: 'test-secret', basePath: 'test', useForBackup: false,
  useForSync: false, useForDownloads: false, ignoreCertificate: false, updatedAt: 1, ...fields });
function storageModel(initial = [fixture()]) {
  let disk = JSON.stringify(initial); let cached = disk;
  const events = []; const changes = []; const tombstones = [];
  const prefs = {
    async get() { events.push('get'); return cached; },
    async put(key, value) { events.push('put'); cached = value; },
    async flush() { events.push('flush'); disk = cached; }
  };
  const types = profileFactory(...supportArgs, { async getPreferences() { return prefs; } }, {
    recordClear(...args) { tombstones.push(['clear', ...args]); },
    recordDeletion(...args) { tombstones.push(['delete', ...args]); }
  }, { get() { return changes.length; }, setOrCreate(key, value) { changes.push(value); } });
  return { store: new types.RemoteStorageProfileStore(), fresh: () => new types.RemoteStorageProfileStore(),
    prefs, events, changes, tombstones, disk: () => disk, cached: () => cached };
}

test('remote profile edits persist every field across reopen and cold reload, without losing other profiles', async () => {
  const m = storageModel([fixture(), fixture({ id: 'other' })]);
  const edited = fixture({ name: 'After', url: 'http://changed.invalid/dav', port: '5005', username: 'new-user',
    password: 'new-test-secret', basePath: 'new-folder', useForBackup: true, useForSync: true,
    useForDownloads: true, ignoreCertificate: true, updatedAt: 2 });
  await m.store.upsert({}, edited);
  assert.deepEqual(m.store.getProfile('fixture'), edited);
  const cold = m.fresh(); await cold.ensureLoaded({});
  assert.deepEqual(cold.getProfile('fixture'), edited);
  assert.equal(cold.getProfiles().length, 2); assert.equal(m.changes.length, 1);
  await m.store.remove({}, 'fixture');
  const removed = m.fresh(); await removed.ensureLoaded({});
  assert.equal(removed.getProfile('fixture'), null); assert.equal(removed.getProfiles().length, 1);
});

test('remote profile writes serialize concurrent edits and removal, and notify only after durable flush', async () => {
  const m = storageModel(); await m.store.ensureLoaded({});
  let release; const pending = new Promise(resolve => { release = resolve; });
  const flush = m.prefs.flush; let first = true;
  m.prefs.flush = async () => { if (first) { first = false; await pending; } await flush(); };
  const write = m.store.upsert({}, fixture({ name: 'After' }));
  const add = m.store.upsert({}, fixture({ id: 'added' }));
  const remove = m.store.remove({}, 'fixture');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(m.store.getProfile('fixture').name, 'Before'); assert.equal(m.changes.length, 0);
  release(); await Promise.all([write, add, remove]);
  assert.deepEqual(m.store.getProfiles().map(p => p.id), ['added']);
  assert.deepEqual(JSON.parse(m.disk()).map(p => p.id), ['added']);
  assert.equal(m.changes.length, 3);
});

test('failed profile writes do not publish or retain unpersisted values, and subsequent saves recover', async () => {
  for (const stage of ['put', 'flush']) {
    const m = storageModel(); await m.store.ensureLoaded({});
    const original = m.prefs[stage]; let once = true;
    m.prefs[stage] = async (...args) => { if (once) { once = false; throw Error('storage failure'); }
      return original(...args); };
    await assert.rejects(m.store.upsert({}, fixture({ name: 'After' })), /Remote storage save failed/);
    assert.equal(m.store.getProfile('fixture').name, 'Before');
    assert.equal(JSON.parse(m.cached())[0].name, 'Before'); assert.equal(JSON.parse(m.disk())[0].name, 'Before');
    assert.equal(m.changes.length, 0); assert.equal(m.tombstones.length, 0);
    const cold = m.fresh(); await cold.ensureLoaded({}); assert.equal(cold.getProfile('fixture').name, 'Before');
    await m.store.upsert({}, fixture({ name: 'Retry' }));
    assert.equal(m.store.getProfile('fixture').name, 'Retry'); assert.equal(m.changes.length, 1);
  }
  const m = storageModel(); await m.store.ensureLoaded({});
  m.prefs.flush = async () => { throw Error('storage failure'); };
  await assert.rejects(m.store.remove({}, 'fixture'), /Remote storage save failed/);
  assert.equal(m.store.getProfiles().length, 1); assert.equal(m.tombstones.length, 0);
});

test('simultaneous initial profile loads share one read, and read failure never overwrites stored profiles', async () => {
  const m = storageModel();
  await Promise.all([m.store.ensureLoaded({}), m.store.ensureLoaded({}), m.store.ensureLoaded({})]);
  assert.equal(m.events.filter(e => e === 'get').length, 1);
  const failed = storageModel(); const get = failed.prefs.get;
  failed.prefs.get = async () => { throw Error('read failure'); };
  await assert.rejects(failed.store.upsert({}, fixture({ id: 'new' })), /read failure/);
  assert.equal(failed.events.includes('put'), false); assert.equal(JSON.parse(failed.disk())[0].id, 'fixture');
  failed.prefs.get = get; await failed.store.upsert({}, fixture({ id: 'new' }));
  assert.equal(failed.store.getProfiles().length, 2);
});

const panelSource = read('entry/src/main/ets/components/RemoteStoragePanel.ets').replaceAll('\r\n', '\n');
function panelMethod(name) {
  const start = panelSource.search(new RegExp('^  private (?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return executable(panelSource.slice(start, panelSource.indexOf('\n  }', start) + 4));
}

test('remote profile rows invalidate stale closures and reopening always resolves latest store values by ID', () => {
  assert.match(panelSource, /profile\.id \+ ':' \+ this\.profilesRevision\.toString\(\)/);
  assert.match(panelMethod('reloadProfiles'), /this\.profilesRevision\+\+/);
  const current = fixture({ name: 'After' });
  const row = Function('remoteStorageProfileStore', 'return {' + panelMethod('openProfile') + '};')({
    getProfile(id) { return id === current.id ? current : null; }
  });
  row.openProfile(fixture()); assert.equal(row.editorProfile.name, 'After'); assert.equal(row.editorVisible, true);
});

test('remote editor awaits save, blocks double submits, retains draft on failure and exposes localized error', async () => {
  let release; let count = 0;
  const row = Function('uiText', 'return {' + panelMethod('submitDraft') + '};')(x => x);
  const messages = [];
  Object.assign(row, { busy: false, currentDraft: () => fixture({ name: 'After' }),
    onSave: () => { count++; return new Promise(resolve => { release = resolve; }); },
    showFloating: message => messages.push(message) });
  const save = row.submitDraft(false); await row.submitDraft(false);
  assert.equal(count, 1); assert.equal(row.busy, true);
  release('Remote storage save failed'); await save;
  assert.equal(row.busy, false); assert.deepEqual(messages, ['Remote storage save failed']);
  assert.equal(row.currentDraft().name, 'After');
  row.onSave = async () => { throw Error('private remote endpoint'); };
  await row.submitDraft(false); assert.equal(messages.at(-1), 'Remote storage save failed');
  row.onSave = async () => ''; await row.submitDraft(false); assert.equal(row.statusText, '');
  assert.match(panelSource, /return this\.saveProfile\(profile\)/);
});

test('failed remote save never closes the editor, refreshes configuration, or reports Saved', async () => {
  const row = Function('getAbilityContext', 'remoteStorageProfileStore', 'uiText', 'remoteStorageSyncService',
    'return {' + panelMethod('saveProfile') + '};')(() => ({}), {
      async upsert() { throw Error('private endpoint'); }
    }, x => x, { refreshConfiguration() { assert.fail('must not refresh failed save'); } });
  Object.assign(row, { editorVisible: true });
  assert.equal(await row.saveProfile(fixture()), 'Remote storage save failed');
  assert.equal(row.editorVisible, true); assert.notEqual(row.panelStatus, 'Saved');
});

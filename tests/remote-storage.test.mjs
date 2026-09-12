import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

// Only erase the types used by these pure functions, not their implementation.
function executable(source) {
  return source.replace(/^import[\s\S]*?from '[^']+';\r?\n/gm, '')
    .replace(/\bexport /g, '')
    .replace(/\b(private|readonly|protected|public) /g, '')
    .replace(/interface \w+ \{[^}]*\}/g, '')
    .replace(/ as (?:RemoteStorageProfile\[\] \| null|RemoteStorageProfile\[\]|RemoteStorageProfile)/g, '')
    .replace(/: (?:common\.UIAbilityContext \| null|common\.UIAbilityContext|Promise<RemoteStorageProfile \| null>|Promise<RemoteStorageProfile\[\]>|Promise<boolean>|Promise<void>|RemoteStorageProfile \| null|RemoteStorageProfile\[\]|RemoteStorageProfile|RemoteStorageListEntry \| null|RemoteStorageListEntry\[\]|RemoteStorageListEntry|RegExpExecArray \| null|RegExp|string\[\]|string|number|boolean|void)(?:\[\])?/g, '');
}

const support = Function(executable(read('entry/src/main/ets/services/RemoteStorageSupport.ets')) +
  '\nreturn { normalizeRemoteStorageUrl, normalizeRemoteStorageBasePath, remoteStorageJoinPath,' +
  ' remoteStorageUrlForPath, remoteStorageRelativePathFromHref, decodeWebDavXmlEntities,' +
  ' webDavStatusMessage, parseWebDavMultiStatus, createRemoteStorageProfileId, isValidRemoteStorageUrl,' +
  ' remoteStorageHost, normalizeRemoteStoragePort, remoteStoragePortFromUrl, remoteStorageUrlWithoutPort,' +
  ' remoteStorageApplyPort };')();

const profiles = Function('createRemoteStorageProfileId', 'isValidRemoteStorageUrl', 'normalizeRemoteStorageBasePath',
  'normalizeRemoteStorageUrl', 'remoteStorageHost', 'normalizeRemoteStoragePort', 'remoteStorageApplyPort',
  executable(read('entry/src/main/ets/services/RemoteStorageProfiles.ets')) +
  '\nreturn { parseRemoteStorageProfiles, normalizeRemoteStorageProfile, remoteStorageProfileForPurpose,' +
  ' remoteStorageProfileSummary };')(support.createRemoteStorageProfileId, support.isValidRemoteStorageUrl,
  support.normalizeRemoteStorageBasePath, support.normalizeRemoteStorageUrl, support.remoteStorageHost,
  support.normalizeRemoteStoragePort, support.remoteStorageApplyPort);

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

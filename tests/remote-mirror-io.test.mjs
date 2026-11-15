import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/services/RemoteStorageSyncService.ets', import.meta.url),
  'utf8').replaceAll('\r\n', '\n');
const start = source.indexOf('async function readMirrorFileSnapshot(');
const implementation = source.slice(start, source.indexOf('\n}', start) + 2)
  .replace(': string', '').replace(': Promise<MirrorFileSnapshot | null>', '');

function reader({ size = 1300000, partial = 90000, endEarly = false, changed = false, replaced = false, openFails = false,
  readFails = false } = {}) {
  const content = Uint8Array.from({ length: size }, (_, i) => i % 251);
  let position = 0;
  let stats = 0;
  let closed = 0;
  let reads = 0;
  const fs = {
    OpenMode: { READ_ONLY: 0 },
    async open() { if (openFails) throw Error('open failed'); return { fd: 42 }; },
    async stat(fd) {
      assert.equal(fd, stats === 0 ? 42 : '/file');
      stats++;
      return { size, ino: replaced && stats > 1 ? 2 : 1,
        mtime: changed && stats > 1 ? 101 : 100, isFile: () => true };
    },
    async read(fd, target, options) {
      assert.equal(fd, 42);
      assert.ok(target.byteLength <= 512 * 1024);
      assert.equal(options.offset, undefined);
      reads++;
      if (readFails) throw Error('read failed');
      if (endEarly && reads > 1) return 0;
      const count = Math.min(partial, options.length, content.length - position);
      new Uint8Array(target).set(content.subarray(position, position + count));
      position += count;
      return count;
    },
    async close(fd) { assert.equal(fd, 42); closed++; }
  };
  return { read: Function('fs', implementation + ';return readMirrorFileSnapshot;')(fs), content,
    closed: () => closed, reads: () => reads };
}

test('mirror file reads yield through asynchronous bounded chunks and preserve partial reads', async () => {
  const env = reader();
  const snapshot = await env.read('/file');
  assert.deepEqual(new Uint8Array(snapshot.data), env.content);
  assert.equal(snapshot.mtime, 100000);
  assert.ok(env.reads() > 3);
  assert.equal(env.closed(), 1);
  assert.ok(!implementation.includes('Sync('));
});

test('mirror file reads reject changing/truncated data and close descriptors on failure', async () => {
  for (const options of [{ endEarly: true }, { changed: true }, { replaced: true }, { readFails: true }, { size: 0 }]) {
    const env = reader(options);
    assert.equal(await env.read('/file'), null);
    assert.equal(env.closed(), 1);
  }
  const missing = reader({ openFails: true });
  assert.equal(await missing.read('/file'), null);
  assert.equal(missing.closed(), 0);
});

test('mirror scanning uses async metadata and records the timestamp associated with uploaded bytes', () => {
  const mirror = source.slice(source.indexOf('private async syncDownloadFiles('),
    source.indexOf('private mergeManifestEntries('));
  assert.ok(!mirror.includes('fs.statSync('));
  assert.ok(!mirror.includes('fs.listFileSync('));
  assert.match(mirror, /await readMirrorFileSnapshot\(/);
  assert.match(mirror, /mtime: snapshot\.mtime/);
  assert.match(mirror, /if \(uploadedHere < gallery\.files\.length\) \{[\s\S]*?this\.downloadsDirty = true;/);
});

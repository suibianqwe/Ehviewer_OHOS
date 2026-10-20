import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../entry/src/main/ets/services/ReaderSuperResolutionService.ets',
  import.meta.url), 'utf8').replaceAll('\r\n', '\n');

// Execute production lifecycle/queue methods, mocking only native copy and enhancement work.
function method(name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4)
    .replace(/\bprivate /g, '')
    .replace(/new Promise<image.PixelMap \| undefined>/g, 'new Promise')
    .replace(/: \(value: image.PixelMap \| undefined\) => void/g, '')
    .replace(/: Promise<(?:image.PixelMap \| undefined|void)>/g, '')
    .replace(/: (?:image.PixelMap|ReaderSuperResolutionEntry|ReaderSuperResolutionTask|number|string|boolean|void|Error \| Object \| string)\b(?: \| undefined)?/g, '');
}

function deferred() {
  let resolve, reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

function pixelMap() {
  return {
    releases: 0,
    getImageInfoSync: () => ({ size: { width: 1500, height: 2000 } }),
    async release() { this.releases++; }
  };
}

function service() {
  const methods = ['acquire', 'acquirePixelMap', 'acquireEntry', 'prepareSourcePixelMap',
    'updatePriority', 'release', 'clear', 'enqueue', 'sortQueue', 'processNext', 'process',
    'finishTask', 'isEntryActive', 'removeFromQueue', 'disposeEntry',
    'releasePixelMap', 'releaseOwnedSourcePixelMap'];
  const model = Function('effectiveReaderSuperResolutionEngine', 'READER_SUPER_RESOLUTION_ENGINE_DETAIL',
    'hilog', 'DOMAIN', 'TAG', 'return {' + methods.map(method).join(',\n') + '};')(
      engine => engine, 'Detail enhancer', { info() {}, warn() {} }, 0, 'test');
  return Object.assign(model, {
    entries: new Map(), queue: [], activeTask: undefined, nextSequence: 0, copies: [], work: [],
    copyCompatibleSdrPixelMap(input) {
      const request = { ...deferred(), input, output: pixelMap() };
      this.copies.push(request);
      return request.promise;
    },
    runEnhancement(entry) {
      const request = { ...deferred(), entry, output: pixelMap() };
      this.work.push(request);
      return request.promise;
    }
  });
}

const flush = () => new Promise(resolve => setImmediate(resolve));
async function finishCopy(state, index = 0) {
  state.copies[index].resolve(state.copies[index].output);
  await flush();
}
async function finishWork(state, index = 0) {
  state.work[index].resolve(state.work[index].output);
  await flush();
}

for (const engine of ['Detail enhancer', 'Core Vision AI']) {
  test(engine + ': cancelling 200 in-flight copies leaves no entries or PixelMaps', async () => {
    const state = service();
    for (let i = 0; i < 200; i++) {
      const pending = state.acquirePixelMap('page-' + i, pixelMap(), 0, 1500, 2000, engine);
      assert.equal(state.entries.get('page-' + i).references, 1);
      state.release('page-' + i);
      await finishCopy(state, i);
      assert.equal(await pending, undefined);
      assert.equal(state.copies[i].output.releases, 1);
    }
    assert.equal(state.entries.size, 0);
    assert.equal(state.work.length, 0);
    assert.equal(state.queue.length, 0);
  });

  test(engine + ': a 200-page completed session releases every input and output', async () => {
    const state = service();
    for (let i = 0; i < 200; i++) {
      const key = 'page-' + i;
      const pending = state.acquirePixelMap(key, pixelMap(), 0, 1500, 2000, engine);
      await finishCopy(state, i);
      await finishWork(state, i);
      assert.equal(await pending, state.work[i].output);
      state.release(key);
      assert.equal(state.copies[i].output.releases, 1);
      assert.equal(state.work[i].output.releases, 1);
      assert.equal(state.entries.size, 0);
    }
    assert.equal(state.activeTask, undefined);
    assert.equal(state.queue.length, 0);
  });
}

test('prefetch and viewport share one copy and result until the last reference releases', async () => {
  const state = service();
  const input = pixelMap();
  const first = state.acquirePixelMap('page', input, 2);
  const second = state.acquirePixelMap('page', input, 0);
  assert.equal(first, second);
  assert.equal(state.copies.length, 1);
  assert.equal(state.entries.get('page').references, 2);
  state.release('page');
  await finishCopy(state);
  assert.equal(state.work.length, 1);
  await finishWork(state);
  assert.equal(await first, state.work[0].output);
  assert.equal(await second, await first);
  assert.equal(state.copies[0].output.releases, 1);
  assert.equal(state.work[0].output.releases, 0);
  const cached = await state.acquirePixelMap('page', input);
  assert.equal(cached, await first);
  assert.equal(state.copies.length, 1);
  state.release('page');
  assert.equal(cached.releases, 0);
  state.release('page');
  assert.equal(cached.releases, 1);
  assert.equal(input.releases, 0);
  assert.equal(state.entries.size, 0);
});

test('clear during copying releases late copies without reviving the reader', async () => {
  const state = service();
  const pending = ['a', 'b'].map(key => state.acquirePixelMap(key, pixelMap()));
  state.clear();
  await finishCopy(state, 0);
  await finishCopy(state, 1);
  assert.deepEqual(await Promise.all(pending), [undefined, undefined]);
  assert.equal(state.entries.size, 0);
  assert.equal(state.work.length, 0);
  assert.ok(state.copies.every(copy => copy.output.releases === 1));
});

test('a cancelled copy cannot overwrite or release a newer request with the same key', async () => {
  const state = service();
  const old = state.acquirePixelMap('page', pixelMap());
  state.release('page');
  const current = state.acquirePixelMap('page', pixelMap());
  const currentEntry = state.entries.get('page');
  await finishCopy(state, 1);
  await finishCopy(state, 0);
  assert.equal(await old, undefined);
  assert.equal(state.entries.get('page'), currentEntry);
  assert.equal(state.copies[0].output.releases, 1);
  assert.equal(state.copies[1].output.releases, 0);
  await finishWork(state);
  assert.equal(await current, state.work[0].output);
  state.release('page');
  assert.equal(state.entries.size, 0);
});

test('copy failures are shared, remain releasable and allow a fresh request', async () => {
  const state = service();
  const first = state.acquirePixelMap('page', pixelMap());
  const second = state.acquirePixelMap('page', pixelMap());
  state.copies[0].reject(new Error('copy failed'));
  assert.deepEqual(await Promise.all([first, second]), [undefined, undefined]);
  assert.equal(state.entries.get('page').pending, undefined);
  state.release('page');
  state.release('page');
  assert.equal(state.entries.size, 0);
  const retry = state.acquirePixelMap('page', pixelMap());
  await finishCopy(state, 1);
  await finishWork(state);
  assert.equal(await retry, state.work[0].output);
  state.release('page');
});

test('cancellation during enhancement waits to release its input and discards the output', async () => {
  const state = service();
  const pending = state.acquirePixelMap('page', pixelMap());
  await finishCopy(state);
  state.release('page');
  assert.equal(state.copies[0].output.releases, 0);
  await finishWork(state);
  assert.equal(await pending, undefined);
  assert.equal(state.copies[0].output.releases, 1);
  assert.equal(state.work[0].output.releases, 1);
  assert.equal(state.entries.size, 0);
});

test('queued copies preserve priority changes and cancellation frees the queued input', async () => {
  const state = service();
  const active = state.acquire('active', '/page.jpg');
  const pending = state.acquirePixelMap('queued', pixelMap(), 5);
  state.updatePriority('queued', 1);
  await finishCopy(state);
  assert.equal(state.queue[0].priority, 1);
  state.release('queued');
  assert.equal(await pending, undefined);
  assert.equal(state.copies[0].output.releases, 1);
  assert.equal(state.queue.length, 0);
  await finishWork(state);
  assert.equal(await active, state.work[0].output);
  state.release('active');
  assert.equal(state.entries.size, 0);
});

test('file-based requests still share enhancement work without copying', async () => {
  const state = service();
  const a = state.acquire('page', '/page.jpg');
  const b = state.acquire('page', '/page.jpg');
  assert.equal(a, b);
  assert.equal(state.copies.length, 0);
  await finishWork(state);
  assert.equal(await a, await b);
  state.release('page');
  state.release('page');
  assert.equal(state.work[0].output.releases, 1);
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const service = read('services/EhMyTagsService.ets');
const host = read('components/GalleryDetailHostScene.ets');
const scene = read('components/GalleryDetailScenes.ets');
const erase = text => text.replace(/\bprivate /g, '').replace(/: Promise<[^>]+>/g, '')
  .replace(/: (?:GallerySite|MyTagsPage|MyTagItem|MyTagKind|number|string|boolean|void|Error)\b(?:\[\])?(?: \| null)?/g, '');
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function helper(name) {
  const start = service.indexOf('function ' + name + '(');
  return erase(service.slice(start, service.indexOf('\n}', start) + 2));
}
const normalizeTag = Function(helper('normalizeTag') + ';return normalizeTag;')();
const findTag = Function('normalizeTag', helper('findTag') + ';return findTag;')(normalizeTag);
const kind = { Watched: 'watched', Hidden: 'hidden' };
const tag = (fields = {}) => ({ id: 10, tag: 'parody:genshin impact', watched: false, hidden: false,
  color: '#ABCDEF', weight: '25', ...fields });
const page = (all = [], site = 1) => ({ all, site, url: 'https://example.invalid/mytags',
  apiUrl: 'https://example.invalid/api.php', apiUid: 123, apiKey: 'synthetic', tagsetId: '0' });

function model(pages) {
  const loads = []; const writes = []; const additions = [];
  const result = Function('normalizeTag', 'findTag', 'MyTagKind', 'parseTagWeight', 'originFromUrl',
    'return {' + ['watchTag', 'hideTag', 'ensureTagKind', 'setExistingTagKind'].map(n => method(service, n)).join(',') + '};')(
      normalizeTag, findTag, kind, value => Number(value), () => 'https://example.invalid');
  Object.assign(result, {
    async load(site) { loads.push(site); const next = pages.shift(); if (next instanceof Error) throw next; return next; },
    async addTag(site, current, text, type) {
      additions.push({ site, current, text, type });
      return page([tag({ watched: type === kind.Watched, hidden: type === kind.Hidden, tag: text })], site);
    },
    ensureOk(response) { if (response.statusCode !== 200) throw Error('HTTP failure'); },
    client: { async postJson(url, body, referer, origin) {
      writes.push({ url, payload: JSON.parse(body), referer, origin }); return { statusCode: 200 };
    } }
  });
  return { result, loads, writes, additions };
}

test('detail subscription preserves canonical English namespace and uses the loaded fallback site', async () => {
  const m = model([page([], 0)]);
  assert.equal(await m.result.watchTag(1, '  parody:genshin impact  '), true);
  assert.deepEqual(m.loads, [1]);
  assert.equal(m.additions[0].text, 'parody:genshin impact');
  assert.equal(m.additions[0].site, 0); assert.equal(m.additions[0].type, kind.Watched);
});

test('already subscribed is case/whitespace tolerant and never writes or changes existing flags', async () => {
  const original = tag({ tag: 'Parody:Genshin   Impact', watched: true, hidden: true });
  const m = model([page([original])]);
  assert.equal(await m.result.watchTag(1, 'parody:genshin impact'), false);
  assert.equal(m.writes.length, 0); assert.equal(m.additions.length, 0);
  assert.equal(original.hidden, true); assert.equal(original.color, '#ABCDEF');
});

test('subscribing an existing hidden tag preserves hidden, color, weight, id and API session', async () => {
  const original = tag({ hidden: true });
  const m = model([page([original]), page([tag({ hidden: true, watched: true })])]);
  assert.equal(await m.result.watchTag(1, original.tag), true);
  assert.equal(m.additions.length, 0); assert.equal(m.writes.length, 1);
  assert.deepEqual(m.writes[0].payload, { method: 'setusertag', apiuid: 123, apikey: 'synthetic', tagid: 10,
    tagwatch: 1, taghide: 1, tagcolor: '#ABCDEF', tagweight: 25 });
  assert.deepEqual(m.loads, [1, 1]);
  await m.result.setExistingTagKind(1, page(), original, kind.Hidden);
  assert.equal(m.writes[1].payload.tagwatch, 0, 'existing My Tags kind-switch behavior is unchanged');
});

test('empty, signed-out, missing credentials, server failure and unconfirmed results cannot report success', async () => {
  const empty = model([]);
  await assert.rejects(empty.result.watchTag(0, ' '), /Enter a tag/);
  assert.equal(empty.loads.length, 0);
  const signedOut = model([Error('valid signed-in session required')]);
  await assert.rejects(signedOut.result.watchTag(0, tag().tag), /signed-in/);
  assert.equal(signedOut.writes.length, 0);
  const credentials = page([tag()]); credentials.apiKey = '';
  const invalid = model([credentials]);
  await assert.rejects(invalid.result.watchTag(1, tag().tag), /API key/);
  const failed = model([page([tag()])]);
  failed.result.client.postJson = async () => ({ statusCode: 403 });
  await assert.rejects(failed.result.watchTag(1, tag().tag), /HTTP failure/);
  const unconfirmed = model([page([tag()]), page([tag()])]);
  await assert.rejects(unconfirmed.result.watchTag(1, tag().tag), /Cannot confirm tag subscription/);
});

const deferred = () => { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; });
  return { promise, resolve, reject }; };
const flush = () => new Promise(resolve => setImmediate(resolve));
function hostModel() {
  const work = deferred(); const calls = []; const messages = []; let revision = 0;
  const result = Function('ehMyTagsService', 'return {' +
    ['subscribeDetailTag', 'hideDetailTag', 'saveAccountTag'].map(n => method(host, n)).join(',') + '};')({
    watchTag(site, text) { calls.push({ site, text }); return work.promise; },
    hideTag(site, text) { calls.push({ site, text, hidden: true }); return work.promise; }
  });
  Object.assign(result, { detailLink: { site: 1, gid: 100 }, tagSubscriptionSaving: false,
    tagSubscriptionGate: { begin() { return ++revision; }, isCurrent(value) { return value === revision; } },
    showToast(message) { messages.push(message); }
  });
  return { result, work, calls, messages };
}

test('host captures the site, prevents double submission, reports outcomes and unlocks retry', async () => {
  for (const changed of [true, false]) {
    const m = hostModel(); m.result.subscribeDetailTag(' '); assert.equal(m.calls.length, 0);
    m.result.subscribeDetailTag('  parody:genshin impact '); m.result.subscribeDetailTag('another:tag');
    assert.deepEqual(m.calls, [{ site: 1, text: 'parody:genshin impact' }]);
    m.work.resolve(changed); await flush();
    assert.equal(m.messages.at(-1), changed ? 'Tag subscribed' : 'Tag already subscribed');
    assert.equal(m.result.tagSubscriptionSaving, false);
  }
  const failed = hostModel(); failed.result.subscribeDetailTag(tag().tag);
  failed.work.reject(Error('network')); await flush();
  assert.equal(failed.messages.at(-1), 'Tag subscription failed: network');
  assert.equal(failed.result.tagSubscriptionSaving, false);
});

test('late subscription results never notify a different or closed detail page', async () => {
  for (const change of [m => { m.result.detailLink.gid++; }, m => { m.result.detailLink.site = 0; },
    m => m.result.tagSubscriptionGate.begin()]) {
    const m = hostModel(); m.result.subscribeDetailTag(tag().tag); change(m);
    m.work.resolve(true); await flush();
    assert.deepEqual(m.messages, ['Subscribing to tag...']);
    assert.equal(m.result.tagSubscriptionSaving, false);
  }
  assert.match(method(host, 'aboutToDisappear'), /tagSubscriptionGate\.begin\(\)/);
  assert.match(method(host, 'loadDetailFromLink'), /tagSubscriptionGate\.begin\(\)/);
});

test('long-press action forwards the unmodified full tag through both detail layers and localizes UI', () => {
  const callback = Function('return {' + method(scene, 'subscribeTag') + '};')();
  const submitted = [];
  Object.assign(callback, { tagVoteTarget: { fullTag: 'parody:genshin impact', tag: '原神' },
    tagVotePanelVisible: true, onSubscribeTag(value) { submitted.push(value); } });
  callback.subscribeTag();
  assert.equal(callback.tagVotePanelVisible, false); assert.deepEqual(submitted, ['parody:genshin impact']);
  assert.match(scene, /onSubscribeTag: this\.onSubscribeTag/);
  assert.match(scene, /label: 'Subscribe to Tag',\s*navigation: true,\s*onTap: this\.onSubscribeTag/);
  assert.match(host, /onSubscribeTag: \(fullTag: string\) => \{ this\.subscribeDetailTag\(fullTag\); \}/);
  assert.match(read('shared/EhTranslations.ets'), /case 'Subscribe to Tag': return '订阅标签'/);
  assert.match(read('shared/EhTranslations.ets'), /case 'Tag already subscribed': return '该标签已订阅'/);
  const http = read('services/EhHttpClient.ets');
  assert.match(http, /postFormOnce\(url, body, referer, origin, ehCookieStore\.getCookieHeaderForUrl\(url\)\)/);
  assert.match(http, /async postJson[\s\S]+ehCookieStore\.getCookieHeaderForUrl\(url/);
});

test('account blocking is additive, confirms the result, and preserves subscription and metadata', async () => {
  const original = tag({ watched: true });
  const m = model([page([original], 0), page([tag({ watched: true, hidden: true })], 0)]);
  assert.equal(await m.result.hideTag(1, '  parody:genshin impact  '), true);
  assert.deepEqual(m.loads, [1, 0]);
  assert.deepEqual(m.writes[0].payload, { method: 'setusertag', apiuid: 123, apikey: 'synthetic', tagid: 10,
    tagwatch: 1, taghide: 1, tagcolor: '#ABCDEF', tagweight: 25 });
  const fresh = model([page([], 0)]);
  assert.equal(await fresh.result.hideTag(1, original.tag), true);
  assert.equal(fresh.additions[0].type, kind.Hidden); assert.equal(fresh.additions[0].site, 0);
  const already = model([page([tag({ hidden: true })])]);
  assert.equal(await already.result.hideTag(1, original.tag), false);
  assert.equal(already.writes.length + already.additions.length, 0);
  const unconfirmed = model([page([original]), page([original])]);
  await assert.rejects(unconfirmed.result.hideTag(1, original.tag), /Cannot confirm tag blocking/);
  const signedOut = model([Error('signed-in required')]);
  await assert.rejects(signedOut.result.hideTag(1, original.tag), /signed-in/);
  const failed = model([page([original])]);
  failed.result.client.postJson = async () => ({ statusCode: 403 });
  await assert.rejects(failed.result.hideTag(1, original.tag), /HTTP failure/);
});

test('account block and local filter are separate actions and account writes are serialized', async () => {
  const callback = Function('return {' + method(scene, 'hideTag') + '};')();
  const submitted = [];
  Object.assign(callback, { tagVoteTarget: { fullTag: tag().tag, tag: '原神' }, tagVotePanelVisible: true,
    onHideTag(value) { submitted.push(value); }, onBlockTag() { assert.fail('local filtering must not run'); } });
  callback.hideTag();
  assert.equal(callback.tagVotePanelVisible, false); assert.deepEqual(submitted, [tag().tag]);
  assert.match(scene, /label: 'Block Tag on Account',[\s\S]*?onTap: this\.onHideTag/);
  assert.match(scene, /label: 'Filter Tag Locally'/);
  assert.match(scene, /onHideTag: this\.onHideTag/);
  assert.match(host, /onHideTag: \(fullTag: string\) => \{ this\.hideDetailTag\(fullTag\); \}/);
  assert.doesNotMatch(method(host, 'saveAccountTag'), /ehFilterStore/);
  assert.doesNotMatch(method(host, 'blockDetailTag'), /ehMyTagsService/);
  for (const changed of [true, false]) {
    const m = hostModel(); m.result.hideDetailTag(tag().tag); m.result.subscribeDetailTag('another:tag');
    assert.deepEqual(m.calls, [{ site: 1, text: tag().tag, hidden: true }]);
    m.work.resolve(changed); await flush();
    assert.equal(m.messages.at(-1), changed ? 'Tag blocked on account' : 'Tag already blocked on account');
    assert.equal(m.result.tagSubscriptionSaving, false);
  }
  const failed = hostModel(); failed.result.hideDetailTag(tag().tag); failed.work.reject(Error('network'));
  await flush(); assert.equal(failed.messages.at(-1), 'Account tag blocking failed: network');
  assert.equal(failed.result.tagSubscriptionSaving, false);
  const stale = hostModel(); stale.result.hideDetailTag(tag().tag); stale.result.tagSubscriptionGate.begin();
  stale.work.resolve(true); await flush(); assert.deepEqual(stale.messages, ['Blocking tag on account...']);
});

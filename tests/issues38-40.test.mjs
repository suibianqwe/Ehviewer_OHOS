import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const host = read('components/GalleryDetailHostScene.ets');
const http = read('services/EhHttpClient.ets');
function erase(source) {
  return source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace(/^(?:export )?interface \w+ \{[\s\S]*?^}\n/gm, '')
    .replace(/\bexport |\bprivate /g, '')
    .replace(/: (?:Map|Set)<[^>]+>/g, '').replace(/new (Map|Set)<[^>]+>/g, 'new $1')
    .replace(/ as Record<[^>]+>/g, '').replace(/ as (?:number|string|boolean)/g, '')
    .replace(/\.(get|setOrCreate)<number>/g, '.$1')
    .replace(/: (?:Error|GalleryStatusStore|GalleryDetailLink|DetailHostNavigationState|RateGalleryParsed|RateGalleryResult|GallerySite|GalleryInfo|RegExpExecArray|RegExp|string|number|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '');
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 4));
}
function fn(source, name) {
  const start = source.indexOf('function ' + name + '('), end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 2));
}
const { commentGalleryIdentity: identity, canOpenCommentGallery: canOpen } = Function(
  erase(read('services/GalleryCommentNavigation.ets')) + '\nreturn {commentGalleryIdentity,canOpenCommentGallery};')();
const rating = Function(erase(read('services/GalleryRatingSupport.ets')) +
  '\nreturn {parseDetailRated,hasPersonalRatingClass,galleryRatingColor};')();
const link = (gid, token = 'abcdef', site = 0, suffix = '') => ({ gid, token, site,
  url: `https://${site ? 'exhentai.org' : 'e-hentai.org'}/g/${gid}/${token}/${suffix}` });
const empty = () => link(0, '');

test('#40 current gallery links, mirrors, anchors and query strings cannot mount another host', () => {
  for (const current of [link(40), link(40, 'ABCDEF', 1)]) {
    for (const target of [link(40), link(40, 'abcdef', 1, '?p=2#c123'), link(40, 'ABCDEF', 0, '#comments')]) {
      assert.equal(canOpen(current, target, []), false);
    }
  }
  assert.equal(canOpen(link(40), link(41), []), true);
  assert.equal(canOpen(link(40), empty(), []), false);
  assert.equal(canOpen(link(40), link(NaN), []), false);
  assert.equal(canOpen(link(40), link(Infinity), []), false);
  assert.equal(canOpen(link(40), link(41), Array(16).fill('ancestor')), false);
});

test('#40 cached self-links and A→B→A cycles are discarded before child creation, preserving comments', () => {
  const cache = new Map();
  const restore = Function('detailHostNavigationCache', 'detailHostCacheKey', 'canOpenCommentGallery',
    'cloneDetailHostLink', 'createEmptyGalleryDetailLink', 'return {' + method(host, 'restoreNavigationState') + '};')(
      cache, identity, canOpen, structuredClone, empty).restoreNavigationState;
  cache.set(identity(link(40)), { showComments: true, showInfo: false, commentGalleryLink: link(40, 'abcdef', 1) });
  assert.equal(restore.call({ detailLink: link(40), ancestorGalleryKeys: [] }).commentGalleryLink.gid, 0);
  cache.set(identity(link(40)), { showComments: true, showInfo: false, commentGalleryLink: link(41) });
  cache.set(identity(link(41)), { showComments: true, showInfo: false, commentGalleryLink: link(40) });
  const first = restore.call({ detailLink: link(40), ancestorGalleryKeys: [] });
  assert.equal(first.commentGalleryLink.gid, 41);
  const second = restore.call({ detailLink: first.commentGalleryLink, ancestorGalleryKeys: [identity(link(40))] });
  assert.equal(second.commentGalleryLink.gid, 0);
  assert.equal(second.showComments, true);
  assert.match(host, /if \(canOpenCommentGallery\(this\.detailLink, this\.commentGalleryLink, this\.ancestorGalleryKeys\)\)/);
  assert.match(host, /ancestorGalleryKeys: this\.ancestorGalleryKeys\.concat\(commentGalleryIdentity\(this\.detailLink\)\)/);
});

test('#40 self-links reveal the mounted detail and retain drafts; ancestor links cannot recurse', () => {
  let target = link(40), writes = 0;
  const open = Function('GallerySite', 'createGalleryDetailLinkFromUrl', 'canOpenCommentGallery',
    'commentGalleryIdentity', 'createEmptyGalleryDetailLink',
    'return {' + method(host, 'openCommentGalleryLink') + '};')(
      { E: 0, Ex: 1 }, () => target, canOpen, identity, empty).openCommentGalleryLink;
  const state = { detailLink: link(40), detailRequestUrl: '', ancestorGalleryKeys: [identity(link(39))],
    commentGalleryLink: empty(), commentDraft: 'keep', renderVersion: 1, showComments: true,
    showInfo: false, saveNavigationState() { writes++; } };
  for (const next of [link(39), null]) { target = next; open.call(state, link(40).url); }
  assert.equal(writes, 0);
  assert.equal(state.commentDraft, 'keep');
  assert.equal(state.renderVersion, 1);
  for (const next of [link(40), link(40, 'ABCDEF', 1, '?p=2#c123')]) {
    state.showComments = true;
    target = next;
    open.call(state, target.url);
    assert.equal(state.showComments, false);
    assert.equal(state.commentGalleryLink.gid, 0);
    assert.equal(state.commentDraft, 'keep');
  }
  assert.equal(writes, 2);
  target = link(41);
  open.call(state, target.url);
  assert.equal(state.commentGalleryLink.gid, 41);
  assert.equal(writes, 3);
});

test('#39 only rating-image classes mark personal votes; ordinary average ratings stay gold', () => {
  const list = read('services/GalleryListParser.ets');
  const parseListRated = Function('hasPersonalRatingClass',
    ['escapeRegExp', 'isVoidTag', 'findClassBlock', 'parseRated'].map(name => fn(list, name)).join('\n') +
    '\nreturn parseRated;')(rating.hasPersonalRatingClass);
  for (const cls of ['irr', 'irg', 'irb']) {
    assert.equal(rating.parseDetailRated(`<div id="rating_image" class="ir ${cls}" style="background-position:0 0"></div>`), true);
    assert.equal(rating.parseDetailRated(`<div class='${cls} ir' id='rating_image'></div>`), true);
    assert.equal(rating.hasPersonalRatingClass(`<div class="ir ${cls}"></div>`), true);
    assert.equal(parseListRated(`<div><div class="ir ${cls}"></div></div>`), true);
  }
  for (const html of ['', '<div id="rating_image" class="ir"></div>',
    '<div class="irb"></div><div id="rating_image" class="ir"></div>',
    '<div id="rating_image" data-class="irb" class="ir"></div>',
    '<div id="rating_image" class="ir" title="irb"></div>']) {
    assert.equal(rating.parseDetailRated(html), false);
  }
  assert.notEqual(rating.galleryRatingColor(true), rating.galleryRatingColor(false));
  assert.equal(parseListRated('<div class="ir" title="irb"><span>irb</span></div>'), false);
  const cards = read('components/GalleryCards.ets');
  assert.equal((cards.match(/rated: this\.gallery\.rated/g) ?? []).length, 2);
  assert.match(cards, /galleryStatusStore\.isRated\(this\.galleryGid, this\.rated\)/);
  assert.match(read('components/detail/DetailActions.ets'), /filledColor: galleryRatingColor\(true\)/);
  assert.match(read('services/GalleryDetailParser.ets'), /rated: parseDetailRated\(body\)/);
});

const parseResponse = Function(fn(http, 'parseRateGalleryResponse') + '\nreturn parseRateGalleryResponse;')();
test('#39 rating API uses real rating_avg/rating_cnt fields and rejects error/invalid responses', () => {
  for (const response of [{ rating_avg: 4.36, rating_cnt: 8 }, { rating_avg: '4.36', rating_cnt: '8' },
    { avg_rating: 4.36, rating_count: 8 }]) {
    assert.deepEqual(parseResponse(JSON.stringify(response), 5), { ok: true, message: '', rating: 4.36, ratingCount: 8 });
  }
  for (const response of ['null', '[]', '{}', '<html>sign in</html>', '{"error":"Denied"}',
    '{"rating_avg":8,"rating_cnt":4}', '{"rating_avg":"","rating_cnt":4}',
    '{"rating_avg":3,"rating_cnt":-1}', '{"rating_avg":3,"rating_cnt":1.5}']) {
    assert.equal(parseResponse(response, 5).ok, false, response);
  }
});

function statusStore() {
  const storage = new Map();
  const Store = Function('AppStorage', erase(read('services/GalleryStatusStore.ets')) + '\nreturn GalleryStatusStore;')({
    get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) });
  return new Store();
}
test('#39 immediate rating markers are account-scoped and do not issue repeated notifications', () => {
  const store = statusStore();
  store.setCloudAccount('one');
  store.markRated(40);
  assert.equal(store.isRated(40, false), true);
  assert.equal(store.isRated(41, false), false);
  assert.equal(store.isRated(41, true), true);
  const version = store.ratingAccountVersion();
  store.markRated(40);
  store.setCloudAccount('one');
  assert.equal(store.ratingAccountVersion(), version);
  store.setCloudAccount('two');
  assert.equal(store.isRated(40, false), false);
  assert.notEqual(store.ratingAccountVersion(), version);
});

function ratingHost() {
  const store = statusStore();
  let resolve;
  const callbacks = [];
  const gate = { value: 0, begin() { return ++this.value; }, isCurrent(n) { return n === this.value; } };
  const rate = Function('cloneGalleryDetail', 'galleryStatusStore', 'saveGalleryToHistory',
    'return {' + method(host, 'rateDetail') + '};')(structuredClone, store, d => callbacks.push(d.gid)).rateDetail;
  const state = { detail: { gid: 40, token: 'abcdef', apiUid: 1, apiKey: 'test', rating: 2, ratingCount: 7, rated: false },
    detailLink: link(40), ratingRequestGate: gate, renderVersion: 0, detailStatus: '',
    client: { rateGallery: () => new Promise(done => { resolve = done; }) },
    showToast() {}, onDetailLoaded: d => callbacks.push(d.gid) };
  return { state, store, rate, callbacks, finish: result => resolve(result) };
}
test('#39 success updates personal state, history and parent; failures and stale responses never mark another gallery', async () => {
  for (const mode of ['success', 'failure', 'navigation', 'account', 'closed']) {
    const { state, store, rate, callbacks, finish } = ratingHost();
    rate.call(state, 5);
    if (mode === 'navigation') state.detail.gid = 41;
    if (mode === 'account') store.setCloudAccount('another');
    if (mode === 'closed') state.ratingRequestGate.begin();
    finish({ ok: mode !== 'failure', message: 'test', rating: 4.36, ratingCount: 8 });
    await Promise.resolve(); await Promise.resolve();
    assert.equal(store.isRated(40, false), mode === 'success', mode);
    assert.equal(state.detail.rated, mode === 'success', mode);
    assert.deepEqual(callbacks, mode === 'success' ? [40, 40] : []);
    if (mode === 'success') assert.equal(state.detail.rating, 4.36, 'the aggregate is not overwritten by the user vote');
  }
});

test('#39 rating transport propagates API failures and invalidates only the target detail cache', async () => {
  const cache = [{ key: 'GET\n/g/40/abcdef/\nold-cookie' }, { key: 'GET\n/g/41/abcdef/\nold-cookie' }];
  const source = method(http, 'rateGallery').replace(/: Promise<RateGalleryResult>/g, '');
  const client = Function('GallerySite', 'EhUrl', 'parseRateGalleryResponse', 'httpStatusMessage',
    'networkErrorMessage', 'SHARED_RESPONSE_CACHE', 'return {' + source + '};')({ E: 0 },
    { getApiUrl: () => '/api.php', getGalleryDetailUrl: gid => `/g/${gid}/abcdef/`, getOrigin: () => 'test' },
    parseResponse, () => 'HTTP error', () => 'network', cache);
  client.postJson = async () => ({ statusCode: 200, body: '{"error":"Denied"}' });
  assert.equal((await client.rateGallery(40, 'abcdef', 1, 'test', 5)).ok, false);
  assert.deepEqual(cache.map(x => x.key), ['GET\n/g/41/abcdef/\nold-cookie']);
  client.postJson = async () => ({ statusCode: 200, body: '{"rating_avg":4.36,"rating_cnt":8}' });
  assert.equal((await client.rateGallery(40, 'abcdef', 1, 'test', 5)).rating, 4.36);
});

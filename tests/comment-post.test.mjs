import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const clientSource = read('services/EhHttpClient.ets');
const hostSource = read('components/GalleryDetailHostScene.ets');

// Execute production helpers with only type annotations erased; works on Node 20+.
function erase(source) {
  return source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace(/^(?:export )?interface \w+ \{[\s\S]*?^}\n/gm, '')
    .replace(/\bexport |\bprivate /g, '')
    .replace(/: Promise<[^>]+>/g, '')
    .replace(/: Set<[^>]+>/g, '')
    .replace(/: (?:GalleryDetailParseResult|GalleryTagGroup|GalleryTagInfo|GalleryPreview|GalleryComment|GalleryDetail|GallerySite|CommentPostResult|CommentAnchor|StyleOffset|FormField|RegExpExecArray|RegExp|string|number|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '')
    .replace(/new Set<(?:string|number)>/g, 'new Set');
}
function functionSource(source, name) {
  const start = source.indexOf('function ' + name + '(');
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 2));
}
function methodSource(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 4));
}
const decodeHtmlEntities = Function(erase(read('shared/HtmlEntitySupport.ets')) + '\nreturn decodeHtmlEntities;')();
const parseGalleryDetail = Function('decodeHtmlEntities', 'GalleryCategory',
  erase(read('services/GalleryDetailParser.ets')) + '\nreturn parseGalleryDetail;')(decodeHtmlEntities, { Unknown: 0 });
const { parseCommentPostResponse, COMMENT_POST_UNCONFIRMED } = Function('decodeHtmlEntities', 'parseGalleryDetail',
  erase(read('services/GalleryCommentSubmission.ets')) + '\nreturn {parseCommentPostResponse, COMMENT_POST_UNCONFIRMED};'
)(decodeHtmlEntities, parseGalleryDetail);
const buildFormBody = Function(functionSource(clientSource, 'buildFormBody') + '\nreturn buildFormBody;')();
const GallerySite = { E: 0, Ex: 1 };
const urlSource = read('services/EhUrl.ets');
const EhUrl = Function('GallerySite', 'buildUrl', 'return class EhUrl {' +
  "static HOST_E = 'https://e-hentai.org/'; static HOST_EX = 'https://exhentai.org/';\n" +
  ['getHost', 'getOrigin', 'getGalleryDetailUrl'].map((name) => {
    const start = urlSource.indexOf('  static ' + name + '(');
    const end = urlSource.indexOf('\n  }', start);
    return erase(urlSource.slice(start, end + 4)).replace(/: QueryParam\[\]/g, '');
  }).join('\n') + '\n}')(GallerySite, (url, params) => url + (params.length ? '?' +
    params.map(({ key, value }) => key + '=' + encodeURIComponent(value)).join('&') : ''));

function gallery({ gid = 123, token = 'abc123', apiUid = 42, error = '', comments = true, form = true } = {}) {
  return `<script>var gid = ${gid}; var token = "${token}"; var apiuid = ${apiUid}; var apikey = "abc";</script>
    <h1 id="gn">Test gallery</h1><div id="chd"><p>Comments</p></div>${error}
    ${comments ? `<a name="c9001"></a><div class="c1"><div class="c3">Posted on today by: <a>Tester</a></div>
    <div class="c4"><a>Edit</a></div><div class="c5"><span>0</span></div>
    <div class="c6">你好 &amp; thanks<br />Second line</div></div>` : ''}
    ${form ? '<textarea name="commenttext_new"></textarea>' : ''}`;
}

function client({ login = true, response = { statusCode: 200, body: gallery() }, reject = false } = {}) {
  const calls = [];
  const cookieUrls = [];
  const cache = [];
  const methods = Function('EhUrl', 'GallerySite', 'ehCookieStore', 'buildFormBody', 'parseCommentPostResponse',
    'COMMENT_POST_UNCONFIRMED', 'httpStatusMessage', 'SHARED_RESPONSE_CACHE',
    'return {' + methodSource(clientSource, 'postComment') + '};')(
      EhUrl, GallerySite, {
        getCookieDebugSummaryForUrl: () => ({ hasLogin: login }),
        getCookieHeaderForUrl: (url) => { cookieUrls.push(url); return 'ipb_member_id=42; ipb_pass_hash=fixture'; }
      }, buildFormBody, parseCommentPostResponse, COMMENT_POST_UNCONFIRMED, (status) => 'HTTP ' + status, cache);
  return Object.assign(methods, {
    calls, cookieUrls, cache,
    async postFormOnce(...args) {
      calls.push(args);
      if (reject) throw new Error('timeout after body sent');
      return response;
    },
    postForm() { throw new Error('retrying transport must not be used for comments'); }
  });
}

test('parses a successful response with production gallery/comment/entity parsers', () => {
  const result = parseCommentPostResponse(gallery(), 123, 'abc123');
  assert.equal(result.ok, true);
  assert.equal(result.comments.length, 1);
  assert.equal(result.comments[0].id, '9001');
  assert.equal(result.comments[0].user, 'Tester');
  assert.match(result.comments[0].content, /你好 &amp; thanks/);
});

test('HTTP 200 site validation errors are not mistaken for existing-comment success', () => {
  const result = parseCommentPostResponse(gallery({ error: '<p style="color:red">Wait &amp; <b>try later</b>.</p>' }),
    123, 'abc123');
  assert.equal(result.ok, false);
  assert.equal(result.message, 'Wait & try later .');
  assert.deepEqual(result.comments, []);
});

test('rejects login/protection pages, mismatched galleries and incomplete responses', () => {
  for (const body of ['<html>Sign in</html>', gallery({ gid: 456 }), gallery({ token: 'def456' }),
    gallery({ apiUid: -1 }), gallery({ form: false }), gallery({ comments: false })]) {
    const result = parseCommentPostResponse(body, 123, 'abc123');
    assert.equal(result.ok, false);
    assert.equal(result.message, COMMENT_POST_UNCONFIRMED);
  }
});

test('posts UTF-8 multiline text once with matching E/Ex URL, Cookie, Referer and Origin', async () => {
  for (const site of [GallerySite.E, GallerySite.Ex]) {
    const transport = client();
    const message = '你好 & + = 😀\nSecond line';
    const result = await transport.postComment(123, 'abc123', '  ' + message + '\n', site);
    assert.equal(result.ok, true);
    assert.equal(transport.calls.length, 1);
    const [url, body, referer, origin, cookie] = transport.calls[0];
    assert.equal(url, EhUrl.getHost(site) + 'g/123/abc123/?hc=1');
    assert.equal(referer, url);
    assert.equal(origin, EhUrl.getOrigin(site));
    assert.deepEqual([...new URLSearchParams(body)], [['commenttext_new', message]]);
    assert.equal(cookie, 'ipb_member_id=42; ipb_pass_hash=fixture');
    assert.deepEqual(transport.cookieUrls, [url]);
  }
});

test('empty drafts, invalid identities and logged-out accounts make no POST', async () => {
  const transport = client();
  for (const [gid, token, text] of [[123, 'abc123', ' \n\t'], [0, 'abc123', 'x'], [123, '../bad', 'x']]) {
    assert.equal((await transport.postComment(gid, token, text)).ok, false);
  }
  assert.equal(transport.calls.length, 0);
  const loggedOut = client({ login: false });
  assert.equal((await loggedOut.postComment(123, 'abc123', 'x')).message, 'Sign in is required');
  assert.equal(loggedOut.calls.length, 0);
});

test('HTTP errors/timeouts are not retried; only the submitted gallery cache is invalidated', async () => {
  for (const options of [{ reject: true }, { response: { statusCode: 503, body: 'Unavailable' } }, {}]) {
    const transport = client(options);
    const other = { key: 'GET\nhttps://e-hentai.org/g/456/abc123/\nref\ncookie' };
    transport.cache.push(other, { key: 'GET\nhttps://e-hentai.org/g/123/abc123/?p=2\nref\ncookie' });
    const result = await transport.postComment(123, 'abc123', 'x');
    assert.equal(result.ok, !options.reject && !options.response);
    assert.equal(transport.calls.length, 1);
    assert.deepEqual(transport.cache, [other]);
    if (options.reject) assert.equal(result.message, COMMENT_POST_UNCONFIRMED);
  }
});

function host() {
  const gateSource = read('services/HttpRequestLifecycle.ets');
  const start = gateSource.indexOf('export class AsyncRequestGate');
  const end = gateSource.indexOf('\n}', start);
  const Gate = Function(erase(gateSource.slice(start, end + 2)) + '\nreturn AsyncRequestGate;')();
  const methods = Function('cloneGalleryDetail', 'COMMENT_POST_UNCONFIRMED',
    'return {' + methodSource(hostSource, 'postDetailComment') + '};')(structuredClone, COMMENT_POST_UNCONFIRMED);
  let resolve;
  const pending = new Promise((done) => { resolve = done; });
  return Object.assign(methods, {
    commentPostGate: new Gate(), commentPosting: false, detailLoaded: true,
    commentDraft: 'my draft', commentPostStatus: '',
    detail: { gid: 123, token: 'abc123', comments: [], title: 'preserve title' }, detailLink: { site: 0 },
    renderVersion: 0, posted: 0, loaded: [], toasts: [], resolve,
    client: { postComment() { methods.posted++; return pending; } },
    onDetailLoaded(value) { this.loaded.push(value); }, showToast(value) { this.toasts.push(value); }
  });
}

test('double taps issue one request; success updates comments and clears only this draft', async () => {
  const state = host();
  const first = state.postDetailComment();
  await state.postDetailComment();
  assert.equal(state.posted, 1);
  assert.equal(state.commentPosting, true);
  const result = parseCommentPostResponse(gallery(), 123, 'abc123');
  state.resolve(result);
  await first;
  assert.equal(state.commentPosting, false);
  assert.equal(state.commentDraft, '');
  assert.equal(state.detail.title, 'preserve title');
  assert.deepEqual(state.detail.comments, result.comments);
  assert.equal(state.loaded.length, 1);
  assert.deepEqual(state.toasts, ['Comment posted']);
});

test('failure retains draft and existing comments, and reports the server message', async () => {
  const state = host();
  const pending = state.postDetailComment();
  state.resolve({ ok: false, message: 'Sign in is required', comments: [] });
  await pending;
  assert.equal(state.commentDraft, 'my draft');
  assert.equal(state.commentPostStatus, 'Sign in is required');
  assert.equal(state.commentPosting, false);
  assert.deepEqual(state.loaded, []);
});

test('a late response cannot overwrite the next gallery or clear its draft', async () => {
  const state = host();
  const pending = state.postDetailComment();
  state.commentPostGate.begin();
  state.detail.gid = 456;
  state.commentDraft = 'next gallery';
  state.commentPosting = false;
  state.resolve(parseCommentPostResponse(gallery(), 123, 'abc123'));
  await pending;
  assert.equal(state.detail.gid, 456);
  assert.equal(state.commentDraft, 'next gallery');
  assert.deepEqual(state.detail.comments, []);
  assert.deepEqual(state.toasts, []);
});

test('zero-comment galleries have a composer, which uses the shared input and circular submit button', () => {
  assert.doesNotMatch(methodSource(hostSource, 'openComments'), /comments\.length/);
  assert.match(read('components/detail/DetailComments.ets'), /Button\(uiText\('Write comment'\)/);
  const composer = read('components/detail/CommentComposer.ets');
  assert.match(composer, /backgroundColor\(themeFieldBackground\(\)\)/);
  assert.match(composer, /uiCapsuleButtonBackground\(true\)/);
  assert.match(composer, /\.height\('auto'\)/);
  assert.match(composer, /\.minLines\(1\)/);
  assert.match(composer, /\.align\(Alignment\.Center\)/);
  assert.match(composer, /\.textOverflow\(TextOverflow\.None\)/);
  assert.match(composer, /\.maxLines\(4, \{ overflowMode: MaxLinesMode\.SCROLL \}\)/);
  assert.match(composer, /\.barState\(BarState\.Auto\)/);
  assert.match(composer, /constraintSize\(\{ minHeight: uiSearchFieldHeight\(\), maxHeight: 132 \}\)/);
  assert.match(composer, /Row\(\{ space: 8 \}\)/);
  assert.match(composer, /Button\(\{ type: ButtonType\.Circle, stateEffect: true \}\)/);
  assert.match(composer, /\.width\(uiSearchFieldHeight\(\)\)/);
  assert.match(composer, /\.height\(uiSearchFieldHeight\(\)\)/);
  assert.match(composer, /backgroundColor\(themeTransparentColor\(\)\)/);
  assert.match(composer, /backgroundEffect\(uiTitleBarBackgroundEffect\(\)\)/);
  assert.doesNotMatch(composer, /\.height\(88\)/);
  assert.match(composer, /enabled\(!this.posting && this.draft.trim\(\).length > 0\)/);
  assert.doesNotMatch(composer, /onSubmit/); // Enter inserts a newline; only the explicit button publishes.
  const scene = read('components/reader/scenes/ReaderAuxScenes.ets');
  assert.match(scene, /CommentComposer\(\{/);
  assert.match(scene, /KeyboardAvoidMode\.RESIZE_WITH_CARET/);
  assert.match(scene, /setKeyboardAvoidMode\(this.previousKeyboardAvoidMode\)/);
  assert.match(hostSource, /aboutToDisappear\(\): void \{\s*this.commentPostGate.begin\(\)/);
});

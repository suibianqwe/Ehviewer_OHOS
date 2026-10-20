import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const checkerSource = read('services/EhUpdateChecker.ets');
const parserSource = read('services/GitHubReleaseParser.ets');
const repo = 'https://github.com/suibianqwe/Ehviewer_OHOS';
const api = 'https://api.github.com/repos/suibianqwe/Ehviewer_OHOS/releases/latest';

// Execute the production helpers after erasing their small, explicit set of ArkTS annotations.
function erase(source) {
  return source.replace(/\bexport |\bprivate /g, '')
    .replace(/ as (?:Record<string, string>|GitHubReleaseJson|Object|string)/g, '')
    .replace(/: Promise<[^>]+>(?: \| null)?/g, '')
    .replace(/: (?:http\.HttpResponse|http\.HttpRequestOptions|ReleaseInfo|UpdateCheckResult|AppVersionInfo|EhRequestPlan|GitHubReleaseRequestHeader|RegExpExecArray|string|number|boolean|Object|void)\b(?:\[\])?(?: \| null)?/g, '');
}

function functionSource(source, name) {
  const start = source.search(new RegExp('(?:async )?function ' + name + '\\('));
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 2));
}

function loadFunctions(source, names, dependencies = {}) {
  return Function(...Object.keys(dependencies), names.map((name) => functionSource(source, name)).join('\n') +
    '\nreturn {' + names.join(',') + '};')(...Object.values(dependencies));
}

const { decodeHtmlEntities } = loadFunctions(read('shared/HtmlEntitySupport.ets'),
  ['decodeHtmlEntities', 'decodeHtmlEntitiesOnce', 'decodeHtmlEntity', 'decodeNumericHtmlEntity']);
export const releaseParser = loadFunctions(parserSource, ['isStableReleaseTag', 'parseGitHubRelease',
  'parseGitHubReleasePage', 'findGitHubHapLink', 'isReleaseHapUrl', 'absoluteGitHubUrl',
  'htmlAttribute', 'metaContent', 'releaseNotesText'], { EH_REPOSITORY_URL: repo, decodeHtmlEntities });

const page = (tag = 'v0.7.4') => `<html><head>
  <meta content='Release ${tag} · project' property='og:title'>
  <meta property="og:url" content="/suibianqwe/Ehviewer_OHOS/releases/tag/${tag}">
  </head><body><div class="markdown-body tmp-my-3"><h2>Update &amp; fixes</h2>
  <ul><li>First fix</li><li>Second fix</li></ul><div><p>Nested notes</p></div></div>
  <p>Unrelated footer</p></body></html>`;
const assets = (tag = 'v0.7.4') => `<a href="/suibianqwe/Ehviewer_OHOS/releases/download/${tag}/App.hap">App.hap</a>`;
const response = (result, responseCode = 200, header = {}) => ({ result, responseCode, header });
const apiRelease = (tag = 'v0.7.4') => response(JSON.stringify({ tag_name: tag, body: 'Release notes',
  assets: [{ name: 'App.hap', browser_download_url: `${repo}/releases/download/${tag}/App.hap` }] }));

function checkerHarness(respond) {
  let now = 1000000;
  const calls = [];
  const outcomes = [];
  const requests = [];
  const events = [];
  const dependencies = {
    ...releaseParser, EH_REPOSITORY_URL: repo, EH_REPOSITORY_NAME: 'suibianqwe/Ehviewer_OHOS',
    EH_APP_VERSION_NAME: '0.7.3', EH_APP_VERSION_CODE: 703, EH_RELEASE_TAG: 'v0.7.3',
    Date: { now: () => now, parse: Date.parse },
    bundleManager: { BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 },
      getBundleInfoForSelf: async () => ({ versionName: '0.7.3', versionCode: 703 }) },
    http: { RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' } },
    hilog: { warn() {}, info() {} },
    ensureEhHostRules: async () => { events.push('rules'); },
    createEhRequestPlan(url) { events.push('plan'); return { url, host: new URL(url).host, fronted: false }; },
    applyEhNetworkOptions(options) { options.usingProxy = 'configured'; },
    acquireHttpRequest() {
      const request = { retired: false, async request(url, options) {
        calls.push({ url, options });
        return respond(url, options, calls.length);
      } };
      requests.push(request);
      return request;
    },
    markHttpRequestVolatile() {},
    retireHttpRequest(request) { request.retired = true; },
    recordEhRequestOutcome(plan, ok) { outcomes.push([plan.url, ok]); }
  };
  const globals = checkerSource.slice(checkerSource.indexOf('const LATEST_RELEASE_API'),
    checkerSource.indexOf('class EhUpdateChecker'));
  const classStart = checkerSource.indexOf('class EhUpdateChecker');
  const classEnd = checkerSource.indexOf('\n}', classStart);
  const methods = ['getCurrentAppVersion', 'fetchLatestRelease', 'cacheRelease', 'githubHeaderValue',
    'githubRetryAt', 'requireSuccess', 'fetchReleaseResponse', 'buildGitHubReleaseHeader',
    'isVersionNewer', 'parseVersionParts', 'errorMessage'];
  const loaded = Function(...Object.keys(dependencies), erase(globals) +
    erase(checkerSource.slice(classStart, classEnd + 2)) + '\n' +
    methods.map((name) => functionSource(checkerSource, name)).join('\n') +
    '\nreturn {checker: new EhUpdateChecker(), githubRetryAt, isVersionNewer};')(...Object.values(dependencies));
  return { ...loaded, calls, requests, outcomes, events, advance: (ms) => { now += ms; } };
}

test('API release parser accepts stable versions and authentic same-release HAP links', () => {
  const parsed = releaseParser.parseGitHubRelease(apiRelease().result);
  assert.equal(parsed.tagName, 'v0.7.4');
  assert.equal(parsed.htmlUrl, repo + '/releases/tag/v0.7.4');
  assert.equal(parsed.hapDownloadUrl, repo + '/releases/download/v0.7.4/App.hap');
  for (const value of [null, {}, { tag_name: 'garbage' }, { tag_name: 'v0.7.4-beta' },
    { tag_name: 'v0.7.4', draft: true }, { tag_name: 'v0.7.4', prerelease: true }]) {
    assert.equal(releaseParser.parseGitHubRelease(JSON.stringify(value)), null);
  }
});

test('web fallback gets the canonical release, complete nested notes, and decoded entities', () => {
  const parsed = releaseParser.parseGitHubReleasePage(page());
  assert.equal(parsed.tagName, 'v0.7.4');
  assert.equal(parsed.name, 'v0.7.4');
  assert.match(parsed.body, /Update & fixes/);
  assert.match(parsed.body, /• First fix/);
  assert.match(parsed.body, /Nested notes/);
  assert.doesNotMatch(parsed.body, /Unrelated footer/);
  assert.equal(parsed.hapDownloadUrl, parsed.htmlUrl);
});

test('web fallback rejects login/error pages, other repositories, prereleases and tags in notes', () => {
  for (const html of ['Forbidden', '<html><head></head><body>v99.0.0</body></html>',
    page('v0.8.0-beta'), page().replaceAll('suibianqwe/Ehviewer_OHOS', 'someone/other'),
    page().replace('property="og:url"', 'data-property="og:url"'),
    page().replace('content="/suibianqwe', 'content="https://evil.example/suibianqwe')]) {
    assert.equal(releaseParser.parseGitHubReleasePage(html), null);
  }
});

test('HAP links cannot escape the repository, release or filename; never guess an asset name', () => {
  const fallback = repo + '/releases/tag/v0.7.4';
  assert.equal(releaseParser.findGitHubHapLink(assets(), 'v0.7.4', fallback), repo + '/releases/download/v0.7.4/App.hap');
  for (const href of ['https://evil.example/App.hap', '//evil.example/App.hap', 'javascript:alert(1)',
    `${repo}/releases/download/v0.7.3/App.hap`, `${repo}/releases/download/v0.7.4/..%2Fevil.hap`,
    `${repo}/releases/download/v0.7.4/App.zip`, `${repo}/releases/download/v0.7.4/App%ZZ.hap`]) {
    assert.equal(releaseParser.findGitHubHapLink(`<a href="${href}">App.hap</a>`, 'v0.7.4', fallback), fallback);
    const parsed = releaseParser.parseGitHubRelease(JSON.stringify({ tag_name: 'v0.7.4',
      assets: [{ name: 'App.hap', browser_download_url: href }] }));
    assert.equal(parsed.hapDownloadUrl, fallback);
  }
});

test('healthy API is one request and repeat taps use a short successful cache', async () => {
  const h = checkerHarness(() => apiRelease());
  const result = await h.checker.checkLatestRelease();
  assert.equal(result.checked, true);
  assert.equal(result.hasUpdate, true);
  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].options.header.Accept, 'application/vnd.github+json');
  await h.checker.checkLatestRelease();
  assert.equal(h.calls.length, 1);
  h.advance(60001);
  await h.checker.checkLatestRelease();
  assert.equal(h.calls.length, 2);
  assert.deepEqual(h.events, ['rules', 'plan', 'rules', 'plan']);
  assert.ok(h.requests.every((request) => request.retired));
});

test('API 403 rate limit falls back to official latest page and lazy-loaded real HAP asset', async () => {
  const h = checkerHarness((url) => url === api
    ? response('rate limit exceeded', 403, { 'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '4600' })
    : response(url.endsWith('/latest') ? page() : assets()));
  const result = await h.checker.checkLatestRelease();
  assert.equal(result.checked, true);
  assert.equal(result.hasUpdate, true);
  assert.equal(result.latest.hapDownloadUrl, repo + '/releases/download/v0.7.4/App.hap');
  assert.deepEqual(h.calls.map(({ url }) => url), [api, repo + '/releases/latest', repo + '/releases/expanded_assets/v0.7.4']);
  for (const { options } of h.calls) {
    assert.equal(options.usingProxy, 'configured');
    assert.ok(!('Cookie' in options.header));
    assert.ok(!('Authorization' in options.header));
  }
  h.advance(61000);
  await h.checker.checkLatestRelease();
  assert.equal(h.calls.filter(({ url }) => url === api).length, 1, 'honor API reset while still allowing web checks');
  assert.ok(h.requests.every((request) => request.retired));
});

test('retry timing respects Retry-After and rate-reset with case-insensitive/object/JSON headers', () => {
  const h = checkerHarness(() => apiRelease());
  assert.equal(h.githubRetryAt({ 'Retry-After': '120' }, 1000000), 1120000);
  assert.equal(h.githubRetryAt(JSON.stringify({ 'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '4600' }), 1000000), 4600000);
  assert.equal(h.githubRetryAt({ 'retry-after': 'Thu, 01 Jan 1970 00:20:00 GMT' }, 1000000), 1200000);
  assert.equal(h.githubRetryAt({ 'retry-after': 'bad', 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': 'NaN' }, 1000000), 1060000);
});

test('API timeout, invalid JSON and 429 can all use the fallback; current release is not an update', async () => {
  for (const failure of [new Error('timeout'), response('bad JSON'), response('limited', 429)]) {
    const h = checkerHarness((url) => {
      if (url === api) { if (failure instanceof Error) throw failure; return failure; }
      return response(url.endsWith('/latest') ? page('v0.7.3') : assets('v0.7.3'));
    });
    const result = await h.checker.checkLatestRelease();
    assert.equal(result.checked, true);
    assert.equal(result.hasUpdate, false);
    assert.equal(result.latest.tagName, 'v0.7.3');
    assert.ok(h.requests.every((request) => request.retired));
  }
});

test('an unavailable asset fragment retains the real version and safe release-page destination', async () => {
  const h = checkerHarness((url) => url === api ? response('', 403)
    : url.endsWith('/latest') ? response(page()) : response('', 500));
  const result = await h.checker.checkLatestRelease();
  assert.equal(result.checked, true);
  assert.equal(result.hasUpdate, true);
  assert.equal(result.latest.hapDownloadUrl, result.latest.htmlUrl);
});

test('failed or unparseable sources cannot report no updates or reuse an expired successful result', async () => {
  let working = true;
  const h = checkerHarness(() => working ? apiRelease() : response('Forbidden', 403));
  await h.checker.checkLatestRelease();
  working = false;
  h.advance(61000);
  const result = await h.checker.checkLatestRelease();
  assert.equal(result.checked, false);
  assert.equal(result.latest, null);
  assert.match(result.message, /GitHub API: HTTP 403; release page: HTTP 403/);
  assert.doesNotMatch(result.message, /No updates available/);
});

test('simultaneous checks share the request and version ordering compares numeric components', async () => {
  let resolve;
  const pending = new Promise((done) => { resolve = done; });
  const h = checkerHarness(() => pending);
  const first = h.checker.checkLatestRelease();
  const second = h.checker.checkLatestRelease();
  resolve(apiRelease());
  assert.deepEqual(await first, await second);
  assert.equal(h.calls.length, 1);
  assert.equal(h.isVersionNewer('v0.7.10', 'v0.7.9'), true);
  assert.equal(h.isVersionNewer('v0.7.3', 'v0.7.3'), false);
  assert.equal(h.isVersionNewer('v0.6.9', 'v0.7.3'), false);
});

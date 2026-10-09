import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const urlSource = read('services/EhUrl.ets');
const httpSource = read('services/EhHttpClient.ets');
const imageSource = read('services/ReaderImageCache.ets');
const tagsSource = read('services/EhMyTagsService.ets');
const GallerySite = { E: 0, Ex: 1 };

// Execute the production helpers, erasing only their ArkTS annotations (Node 20 compatible).
function executable(source) {
  return source.replace(/\bexport |\breadonly /g, '')
    .replace(/: (?:GallerySite|EhRequestPlan|ImageRequestHeader|RequestHeader|string|number|boolean)\b/g, '');
}
const urlStart = urlSource.indexOf('export class EhUrl {');
const urlEnd = urlSource.indexOf('  static getApiUrl(', urlStart);
assert.ok(urlStart >= 0 && urlEnd > urlStart);
const EhUrl = Function('GallerySite', executable(urlSource.slice(urlStart, urlEnd)) +
  '\n}\nreturn EhUrl;')(GallerySite);

function loadFunction(source, name, dependencies = {}) {
  const start = source.indexOf('function ' + name + '(');
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name + ' must exist');
  return Function(...Object.keys(dependencies), executable(source.slice(start, end + 2)) +
    '\nreturn ' + name + ';')(...Object.values(dependencies));
}
const headers = {};
const browserConstants = {
  CHROME_USER_AGENT: 'test-browser', ANDROID_CHROME_USER_AGENT: 'test-mobile-browser',
  CHROME_ACCEPT: 'text/html', CHROME_ACCEPT_LANGUAGE: 'zh-CN', ANDROID_CHROME_BRAND_HEADER: 'test-brand'
};
for (const name of ['buildRequestHeader', 'buildPostRequestHeader', 'buildJsonRequestHeader',
  'buildMultipartRequestHeader']) {
  headers[name] = loadFunction(httpSource, name, browserConstants);
}
const imageHeader = loadFunction(imageSource, 'buildImageRequestHeader');
const originFromUrl = loadFunction(tagsSource, 'originFromUrl', { EhUrl });

test('EH and Ex root Referer URLs have exactly one trailing slash (#33)', () => {
  assert.equal(EhUrl.getReferer(), 'https://e-hentai.org/');
  for (const [site, host] of [[GallerySite.E, 'e-hentai.org'], [GallerySite.Ex, 'exhentai.org']]) {
    assert.equal(EhUrl.getReferer(site), 'https://' + host + '/');
    assert.equal(EhUrl.getReferer(site), EhUrl.getHost(site));
  }
});

test('Origin stays scheme + host without a path or trailing slash', () => {
  assert.equal(EhUrl.getOrigin(), 'https://e-hentai.org');
  assert.equal(EhUrl.getOrigin(GallerySite.Ex), 'https://exhentai.org');
  assert.equal(originFromUrl('https://exhentai.org/mytags?x=1', GallerySite.E), 'https://exhentai.org');
  assert.equal(originFromUrl('/mytags', GallerySite.Ex), 'https://exhentai.org');
});

test('image headers keep the canonical Referer, original Host and cookie on direct/fronted routes', () => {
  const cookie = 'ipb_member_id=test; ipb_pass_hash=synthetic; igneous=synthetic';
  for (const site of [GallerySite.E, GallerySite.Ex]) {
    for (const fronted of [false, true]) {
      const host = site === GallerySite.Ex ? 's.exhentai.org' : 'ehgt.org';
      const plan = { host, fronted, url: fronted ? 'https://192.0.2.1/cover.webp' : 'https://' + host + '/cover.webp' };
      const header = imageHeader(plan, EhUrl.getReferer(site), cookie);
      assert.equal(header.Referer, site === GallerySite.Ex ? 'https://exhentai.org/' : 'https://e-hentai.org/');
      assert.equal(header.Host, host);
      assert.equal(header.Cookie, cookie);
      assert.ok(!('Origin' in header));
    }
  }
  assert.match(imageSource, /buildImageRequestHeader\(plan, referer, ehCookieStore\.getCookieHeaderForUrl\(imageUrl\)\)/);
});

test('explicit reader page Referers remain intact and anonymous requests omit Cookie', () => {
  const referer = 'https://exhentai.org/s/page-token/12345-2?nl=test';
  const header = imageHeader({ host: 'image.example', fronted: false }, referer, '');
  assert.equal(header.Referer, referer);
  assert.ok(!('Cookie' in header));
});

test('HTML, form, JSON and multipart requests distinguish Referer from Origin', () => {
  for (const site of [GallerySite.E, GallerySite.Ex]) {
    const plan = { host: site === GallerySite.Ex ? 'exhentai.org' : 'e-hentai.org' };
    const referer = EhUrl.getReferer(site);
    const origin = EhUrl.getOrigin(site);
    for (const compatibility of [false, true]) {
      const get = headers.buildRequestHeader(plan, referer, 'test=value', 0, compatibility);
      assert.equal(get.Referer, origin + '/');
      assert.equal(get.Cookie, 'test=value');
      assert.ok(!('Origin' in get));
      const form = headers.buildPostRequestHeader(plan, referer, origin, '', compatibility);
      assert.equal(form.Referer, origin + '/');
      assert.equal(form.Origin, origin);
      assert.ok(!('Cookie' in form));
    }
    for (const header of [headers.buildJsonRequestHeader(plan, referer, origin, 'test=value'),
      headers.buildMultipartRequestHeader(plan, referer, origin, 'test=value', 'multipart/form-data; boundary=test')]) {
      assert.equal(header.Referer, origin + '/');
      assert.equal(header.Origin, origin);
      assert.equal(header.Cookie, 'test=value');
    }
  }
});

test('POST call sites use the Origin helper and image search does not append another slash', () => {
  assert.doesNotMatch(httpSource, /const origin = EhUrl\.(?:getReferer|getHost)\(/);
  assert.doesNotMatch(httpSource, /referer, EhUrl\.(?:getReferer|getHost)\(/);
  assert.doesNotMatch(httpSource, /EhUrl\.getReferer\(site\)\s*\+\s*['"]\/['"]/);
  assert.match(httpSource, /postMultipart\(url, multipart\.body, multipart\.contentType, referer, EhUrl\.getOrigin\(site\)/);
});

test('cover and preview downloads share the corrected root Referer helper', () => {
  const shared = read('shared/EhShared.ets');
  assert.match(shared, /readerImageCache\.ensureCached\(context, url, EhUrl\.getReferer\(currentGallerySite\(\)\)/);
  assert.match(shared, /previewThumbnailCache\.ensureCropped\(context, preview, EhUrl\.getReferer\(currentGallerySite\(\)\)/);
});

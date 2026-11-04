import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const scene = read('components/reader/scenes/ReaderAuxScenes.ets');
const component = read('components/detail/CommentComponents.ets');

function erase(source) {
  return source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace(/^(?:export )?interface \w+ \{[\s\S]*?^}\n/gm, '')
    .replace(/\bexport |\bprivate /g, '')
    .replace(/: Map<[^>]+>/g, '').replace(/new Map<[^>]+>/g, 'new Map')
    .replace(/: (?:GalleryComment|CommentListItem|CommentTextSegment|RegExpExecArray|RegExp|string|number|boolean|void)\b(?:\[\])?(?: \| (?:null|undefined))?/g, '');
}
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?' + name + '\\(', 'm'));
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 4));
}
function fn(source, name) {
  const start = source.indexOf('function ' + name + '(');
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, name);
  return erase(source.slice(start, end + 2));
}

const buildItems = Function(erase(read('services/CommentListSupport.ets')) + '\nreturn buildCommentListItems;')();
const comment = (id, extra = {}) => ({ id: String(id), user: 'test', posted: 'today', content: 'text', score: 0, ...extra });

test('long comment lists retain stable keys and snapshots without creating UI nodes', () => {
  const comments = Array.from({ length: 10000 }, (_, i) => comment(i));
  const first = buildItems(comments, []);
  assert.equal(first.length, 10000);
  assert.equal(new Set(first.map(x => x.key)).size, 10000);
  const again = buildItems(comments, first);
  again.forEach((item, i) => {
    assert.equal(item.key, first[i].key);
    assert.equal(item.comment, first[i].comment);
  });
  assert.match(scene, /LazyForEach\(this\.commentsSource/);
  assert.doesNotMatch(scene, /ForEach\(this\.visibleCommentItems/);
  assert.match(scene, /comment: item\.comment/);
  assert.match(scene, /\.cachedCount\(4\)/);
});

test('votes, edits and permissions invalidate only changed lazy rows, even for in-place mutations', () => {
  const changes = { score: 2, content: 'edited', user: 'changed', posted: 'later', voteUpAble: true,
    voteDownAble: true, voteUpEd: true, voteDownEd: true, voteState: 'voted' };
  for (const [field, value] of Object.entries(changes)) {
    const comments = [comment(1), comment(2)];
    const first = buildItems(comments, []);
    comments[1][field] = value;
    const next = buildItems(comments, first);
    assert.equal(next[0].key, first[0].key);
    assert.notEqual(next[1].key, first[1].key, field);
    assert.equal(next[1].comment[field], value);
    assert.notEqual(first[1].comment[field], value);
  }
});

test('blocking, posting and duplicate IDs preserve unrelated identities', () => {
  const initial = buildItems([comment(1), comment(2), comment(3)], []);
  const blocked = buildItems([comment(1), comment(3)], initial);
  assert.equal(blocked[1].key, initial[2].key);
  const posted = buildItems([comment(1), comment(3), comment(4)], blocked);
  assert.equal(posted[0].key, initial[0].key);
  assert.equal(posted[1].key, initial[2].key);
  const duplicates = buildItems([comment(0), comment(0), comment(''), comment('')], []);
  assert.equal(new Set(duplicates.map(x => x.key)).size, 4);
  assert.deepEqual(buildItems([], posted), []);
});

const decode = Function(erase(read('shared/HtmlEntitySupport.ets')) + '\nreturn decodeHtmlEntities;')();
const plain = Function('decodeHtmlEntities', fn(read('shared/EhTranslations.ets'), 'plainTextFromHtml') +
  '\nreturn plainTextFromHtml;')(decode);
const parse = Function('plainTextFromHtml', fn(component, 'commentPlainTextFromHtml') +
  '\nreturn commentPlainTextFromHtml;')(plain);
const segments = Function('COMMENT_URL_PATTERN', fn(component, 'trimTrailingUrlPunctuation') + '\n' +
  fn(component, 'commentTextSegments') + '\nreturn commentTextSegments;')(/(https?:\/\/[^\s<>"']+|magnet:\?[^\s<>"']+)/gi);

function textModel(translator = { translateComment: async () => 'translated' }) {
  const counts = { parse: 0, split: 0 };
  const Model = Function('commentPlainTextFromHtml', 'commentTextSegments', 'ehTranslationService',
    'return class {' + ['refreshSourceText', 'displaySegments', 'resetTranslation', 'requestTranslationIfNeeded',
      'aboutToDisappear'].map(name => method(component, name)).join('\n') + '\n}')(
    html => { counts.parse++; return parse(html); },
    text => { counts.split++; return segments(text); }, translator);
  const model = Object.assign(new Model(), { html: '', cachedHtml: undefined, sourceText: '', sourceSegments: [],
    cachedTranslation: '', translatedSegments: [], translateComment: false, translatedText: '',
    translationPriority: 2, translationRequestVersion: 0 });
  return { model, counts };
}

test('HTML and links parse once per content change, not per scroll or theme rebuild', () => {
  const { model, counts } = textModel();
  model.html = '<p>A &amp; B<br><a href="https://example.org/g/1/a/">Gallery</a></p>';
  model.resetTranslation();
  const first = model.displaySegments();
  assert.equal(first.map(x => x.text).join(''), 'A & B\nGallery https://example.org/g/1/a/');
  assert.equal(first.find(x => x.url).url, 'https://example.org/g/1/a/');
  for (let i = 0; i < 500; i++) assert.equal(model.displaySegments(), first);
  assert.deepEqual(counts, { parse: 1, split: 1 });
  model.html = '<p>Changed</p>';
  model.resetTranslation();
  assert.equal(model.displaySegments()[0].text, 'Changed');
  assert.deepEqual(counts, { parse: 2, split: 2 });
  model.html = '';
  model.resetTranslation();
  assert.equal(model.displaySegments()[0].text, '');
});

test('translated segments cache independently and disabling translation restores original links', () => {
  const { model, counts } = textModel();
  model.html = 'Original https://example.org';
  const original = model.displaySegments();
  model.translateComment = true;
  model.translatedText = '译文 https://example.org';
  const translated = model.displaySegments();
  for (let i = 0; i < 500; i++) assert.equal(model.displaySegments(), translated);
  assert.deepEqual(counts, { parse: 1, split: 2 });
  model.translateComment = false;
  assert.equal(model.displaySegments(), original);
});

test('translation completion cannot update a removed lazy row', async () => {
  let resolve;
  const { model } = textModel({ translateComment: () => new Promise(done => { resolve = done; }) });
  model.html = 'original';
  model.translateComment = true;
  model.resetTranslation();
  model.aboutToDisappear();
  resolve('stale translated result');
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(model.translatedText, '');
});

test('toolbar animation preserves scroll delta and cannot change list viewport padding', () => {
  assert.match(scene, /\.contentStartOffset\(this\.totalBarHeight\(\)\)/);
  assert.doesNotMatch(scene, /padding\(\{ top: this\.visibleBarHeight\(\)/);
  const frame = Function('nextFloatingToolbarOffset', 'return {' + method(scene, 'handleScrollFrame') + '};')(
    (offset, delta, _y, height) => Math.max(-height, Math.min(0, offset - delta))).handleScrollFrame;
  const model = { toolbarOffsetY: 0, toolbarRestoring: false,
    commentsScroller: { currentOffset: () => ({ yOffset: 100 }) },
    visibleBarHeight() { return 80 + this.toolbarOffsetY; }, totalBarHeight: () => 80,
    restoreToolbarOnReverseScroll() { this.toolbarOffsetY = 0; } };
  for (const delta of [5, 30, 90, 10, -10, -40, 20]) assert.equal(frame.call(model, delta), delta);
  assert.doesNotMatch(scene, /onScrollIndex|translationVisibleStart|translationVisibleEnd/);
  assert.match(scene, /prioritizeVisibleTranslation: true/);
  assert.match(component, /onVisibleAreaChange\(\[0\.0\]/);
  assert.match(component, /this\.commentInViewport \? 2 : 1/);
});

test('composer overlays comments with field-only blur and reserves its measured height at the end', () => {
  const composer = read('components/detail/CommentComposer.ets');
  assert.match(scene, /Stack\(\{ alignContent: Alignment\.BottomStart \}\)/);
  assert.match(scene, /\.contentEndOffset\(this\.composerHeight\)/);
  assert.doesNotMatch(method(scene, 'build'), /\.layoutWeight\(1\)/);
  assert.match(composer, /\.backgroundEffect\(uiBlurredFieldBackgroundEffect\(\)\)/);
  const footer = composer.slice(composer.lastIndexOf(".padding({ left: 16"));
  assert.match(footer, /backgroundColor\(Color\.Transparent\)/);
  assert.doesNotMatch(footer, /backgroundEffect|backgroundBlurStyle/);
  const update = Function('return {' + method(scene, 'updateComposerHeight') + '};')().updateComposerHeight;
  const model = { composerHeight: 62 };
  for (const value of [NaN, Infinity, -10, 0, 62.1]) update.call(model, value);
  assert.equal(model.composerHeight, 62);
  for (const value of [100, 150, 62]) {
    update.call(model, value);
    assert.equal(model.composerHeight, value, 'multiline growth and shrinkage update only the end inset');
  }
});

test('blurred field style supports both themes and falls back to a visible fill without blur capability', () => {
  const style = read('shared/EhUiStyle.ets');
  const helpers = style.slice(style.indexOf('export function uiBlurredFieldBackground('),
    style.indexOf('export function uiSegmentMaterial('))
    .replaceAll('export ', '').replace(/: (?:ResourceColor|BackgroundEffectOptions \| undefined)/g, '');
  assert.ok(helpers.includes('uiBlurredFieldBackgroundEffect'));
  for (const supported of [false, true]) {
    for (const dark of [false, true]) {
      const ui = Function('supportsBackgroundEffect', 'isDarkTheme', 'themeFieldBackground', 'Color', 'AdaptiveColor',
        helpers + '\nreturn { background: uiBlurredFieldBackground, effect: uiBlurredFieldBackgroundEffect };')(
        () => supported, () => dark, () => 'fallback', { Transparent: 'transparent' }, { DEFAULT: 0 });
      assert.equal(ui.background(), supported ? 'transparent' : 'fallback');
      assert.equal(ui.effect() !== undefined, supported);
      if (supported) {
        assert.equal(ui.effect().radius, 24);
        assert.equal(ui.effect().color, dark ? 'rgba(16,22,30,0.58)' : 'rgba(255,255,255,0.72)');
      }
    }
  }
});

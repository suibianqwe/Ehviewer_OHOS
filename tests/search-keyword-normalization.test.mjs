import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

function executable(source) {
  return source
    .replace(/\bexport /g, '')
    .replace(/interface \w+ \{[\s\S]*?\n\}\r?\n/g, '')
    .replace(/: (?:RegExpExecArray \| null|RegExp|Record<string, string>|string\[\]|TagToken\[\]|string|number|boolean|void)/g, '');
}

const logic = Function(executable(read('entry/src/main/ets/services/SearchKeywordNormalization.ets')) +
  '\nreturn { normalizeLegacySearchKeywordValue, normalizeSubmittedSearchKeywordValue };')();

const normalize = (value) => logic.normalizeSubmittedSearchKeywordValue(value);

test('multi-word tag values keep their spaces instead of splitting into new tags', () => {
  assert.equal(normalize('artist:foo bar'), 'artist:foo bar$');
  assert.equal(normalize('f:big breasts'), 'female:big breasts$');
  assert.equal(normalize('artist:foo bar group:another name'), 'artist:foo bar$ group:another name$');
  assert.equal(normalize('female:big breasts$ artist:bai lao shi$'),
    'female:big breasts$ artist:bai lao shi$');
});

test('dollar separated tags and legacy short namespaces are normalized', () => {
  assert.equal(normalize('artist:foo bar$parody:x$'), 'artist:foo bar$ parody:x$');
  assert.equal(normalize('a:some artist$'), 'artist:some artist$');
  assert.equal(normalize('parody:genshin impact$ language:chinese'),
    'parody:genshin impact$ language:chinese$');
});

test('quoted values are unwrapped and terminated', () => {
  assert.equal(normalize('artist:"foo bar"'), 'artist:foo bar$');
  assert.equal(normalize('artist:“foo bar”'), 'artist:foo bar$');
});

test('plain keywords without namespaces are untouched apart from whitespace', () => {
  assert.equal(normalize('foo  bar'), 'foo bar');
  assert.equal(normalize('artist foo bar'), 'artist foo bar');
  assert.equal(normalize(''), '');
});

test('normalization is idempotent', () => {
  for (const value of ['artist:foo bar', 'f:big breasts artist:foo bar l:chinese',
    'artist:foo bar$parody:x$', 'a:some artist$']) {
    const once = normalize(value);
    assert.equal(normalize(once), once, value);
  }
});

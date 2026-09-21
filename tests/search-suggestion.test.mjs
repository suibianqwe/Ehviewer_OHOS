import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const scenes = read('entry/src/main/ets/components/GallerySearchScenes.ets');
const gallery = read('entry/src/main/ets/components/GalleryListContent.ets');

// Only erase the types used by these pure functions, not their implementation.
// Keep the test runner compatible with Node 20 (no native TS loader required).
function executable(source) {
  return source.replace(/\bexport /g, '')
    .replace(/interface \w+ \{[^}]*\}/g, '')
    .replace(/: (?:TagToken\[\]|TagToken|Record<string, string>|RegExpExecArray \| null|RegExp|ActiveTagSearchInput|GalleryUrlMatch \| null|SearchSuggestionItem|TagNamespaceOption|string|number|boolean|void)(?:\[\])?/g, '');
}

const normalization = Function(executable(read('entry/src/main/ets/services/SearchKeywordNormalization.ets')) +
  '\nreturn { normalizeLegacySearchKeywordValue, normalizeSubmittedSearchKeywordValue };')();
const logicStart = scenes.indexOf('const SEARCH_SUGGESTION_RENDER_BATCH:');
const logicEnd = scenes.indexOf('@Component', logicStart);
assert.ok(logicStart >= 0 && logicEnd > logicStart);
const logicSource = scenes.slice(logicStart, logicEnd);

// Use the actual bundled database row, including its fully-qualified English tag.
const row = read('entry/src/main/resources/rawfile/ehtag_translations.tsv').split(/\r?\n/)
  .find((line) => line.startsWith('parody\tparody:genshin impact\t'));
assert.ok(row);
const [namespace, tag, translated, searchText] = row.split('\t');
const entry = { namespace, tag, translated, searchText };
function loadLogic(translationsEnabled = true) {
  const dependencies = {
    ...normalization,
    shouldShowTagTranslations: () => translationsEnabled,
    ehTagTranslationStore: {
      suggest: (query, _limit, namespaces) => entry.searchText.includes(query.toLowerCase()) &&
        (namespaces.length === 0 || namespaces.includes(entry.namespace)) ? [{ ...entry }] : [],
      translate: (ns, value) => ns + ':' + value === entry.tag ? entry.translated : ''
    },
    ehSearchHistoryStore: { getKeywords: () => ['saved query'] }
  };
  return Function(...Object.keys(dependencies), executable(logicSource) +
    '\nreturn { buildSearchSuggestions, applyTagSuggestionToKeyword, normalizeSearchTagToken,' +
    ' searchTagTokens, searchKeywordWithoutTagTokens, searchTagTokenDisplayLabel, searchKeywordForRequest };')
    (...Object.values(dependencies));
}

const method = gallery.match(/private applySearchSuggestion\(suggestion: SearchSuggestionItem\): void \{([\s\S]*?)\r?\n  \}/);
assert.ok(method);
function clickSuggestion(logic, keyword, suggestion) {
  const model = {
    keyword, mode: -1,
    onKeywordChange(value) { this.keyword = value; },
    onSearchModeChange(value) { this.mode = value; }
  };
  Function(...Object.keys(logic), 'ListMode', 'suggestion', method[1])
    .call(model, ...Object.values(logic), { Normal: 0 }, suggestion);
  return model;
}

test('clicking 原神 retains one English namespace and sends a correctly quoted request', () => {
  const logic = loadLogic();
  const input = 'parody:genshin impact';
  const [suggestion] = logic.buildSearchSuggestions(input, 0, []);
  assert.equal(suggestion.title, '原神');
  assert.equal(suggestion.query, 'parody:genshin impact');
  const result = clickSuggestion(logic, input, suggestion);
  assert.equal(result.keyword, 'parody:genshin impact$');
  assert.deepEqual(logic.searchTagTokens(result.keyword), ['parody:genshin impact$']);
  assert.equal(logic.searchKeywordWithoutTagTokens(result.keyword), '');
  assert.equal(logic.searchTagTokenDisplayLabel(result.keyword), '原神');
  assert.equal(logic.searchKeywordForRequest(result.keyword), 'parody:"genshin impact$"');
});

test('selecting a multi-word suggestion removes the entire active input and preserves existing tags', () => {
  const logic = loadLogic();
  const [suggestion] = logic.buildSearchSuggestions('parody:genshin impact', 0, []);
  for (const input of ['parody:genshin impact', 'parody:"genshin impact"', 'p:genshin impact',
    'parody：genshin impact', 'genshin impact']) {
    const keyword = 'artist:miho$ ' + input;
    const result = clickSuggestion(logic, keyword, suggestion);
    assert.equal(result.keyword, 'artist:miho$ parody:genshin impact$', keyword);
    assert.equal(logic.searchKeywordWithoutTagTokens(result.keyword), '', keyword);
    assert.equal(logic.searchKeywordForRequest(result.keyword), 'artist:miho$ parody:"genshin impact$"');
  }
});

test('translation visibility affects labels only, and an existing terminator is not duplicated', () => {
  for (const enabled of [true, false]) {
    const logic = loadLogic(enabled);
    const [suggestion] = logic.buildSearchSuggestions('原神', 0, []);
    assert.equal(suggestion.title, enabled ? '原神' : 'parody:genshin impact');
    const result = clickSuggestion(logic, '原神', { ...suggestion, query: suggestion.query + '$' });
    assert.equal(result.keyword, 'parody:genshin impact$');
    assert.equal(logic.searchTagTokenDisplayLabel(result.keyword), enabled ? '原神' : 'genshin impact');
    assert.equal(logic.searchKeywordForRequest(result.keyword), 'parody:"genshin impact$"');
  }
});

test('history selection is passed through without adding a namespace or terminator', () => {
  const logic = loadLogic();
  const [suggestion] = logic.buildSearchSuggestions('', 0, []);
  const result = clickSuggestion(logic, 'unfinished input', suggestion);
  assert.equal(result.keyword, 'saved query');
  assert.equal(result.mode, -1);
});

test('imported Android keywords terminate every known bare tag', () => {
  const logic = loadLogic();
  const normalize = normalization.normalizeSubmittedSearchKeywordValue;
  assert.equal(normalize('female:sole_female language:chinese'),
    'female:sole_female$ language:chinese$');
  assert.equal(normalize('f:sole_female l:chinese'),
    'female:sole_female$ language:chinese$');
  assert.equal(normalize('female:sole_female$ language:chinese'),
    'female:sole_female$ language:chinese$');
  assert.equal(normalize('female:"big breasts" language:chinese'),
    'female:big breasts$ language:chinese$');
  assert.equal(normalize('unknown:foo bar language:chinese'),
    'unknown:foo bar language:chinese$');
  assert.equal(normalize('artist:foo bar baz'), 'artist:foo bar baz$');
  const keyword = normalize('f:sole_female l:chinese');
  assert.deepEqual(logic.searchTagTokens(keyword), ['female:sole_female$', 'language:chinese$']);
  assert.equal(logic.searchKeywordWithoutTagTokens(keyword), '');
  assert.equal(logic.searchKeywordForRequest(keyword), 'female:sole_female$ language:chinese$');
});

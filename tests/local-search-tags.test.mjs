import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');

function executable(source) {
  return source.replace(/^import[\s\S]*?from '[^']+';\r?\n/gm, '')
    .replace(/\bexport /g, '')
    .replace(/interface \w+ \{[^}]*\}/g, '')
    .replace(/: (?:GalleryTagGroup\[\] \| undefined|string\[\] \| undefined|string \| undefined|RegExpExecArray \| null|LocalGallerySearchOptions|LocalTagQueryParts|GalleryInfo|ListMode(?!\.)|GalleryCategory(?!\.)|RegExp|string|number|boolean|void)(?:\[\])?/g, '');
}

const logic = Function('GalleryCategory', 'ListMode', 'ALL_CATEGORY', 'DEFAULT_ADVANCE_SEARCH',
  executable(read('entry/src/main/ets/services/LocalGallerySearch.ets')) +
  '\nreturn { galleryMatchesLocalSearch };')(
  { None: 0, Unknown: 1 }, { Normal: 0, Tag: 1, Uploader: 2 }, -1, 0);

const options = {
  mode: 0, category: 0, advancedEnabled: false, advancedPanelOpened: false, advanceSearch: 0, minRating: -1
};
const gallery = {
  gid: 42, title: 'Some title', uploader: 'uploader', rating: 5, category: 1,
  simpleTags: ['parody:genshin impact', 'language:chinese']
};

test('local search understands namespaced tag filters outside tag mode', () => {
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:genshin impact$', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:"genshin impact"', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:genshin impact', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'language:chinese', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:other$', options), false);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:genshin impact$ language:chinese', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'parody:genshin impact$ language:japanese', options), false);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'Some title', options), true);
  assert.equal(logic.galleryMatchesLocalSearch(gallery, 'missing words', options), false);
});

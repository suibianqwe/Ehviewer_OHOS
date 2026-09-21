import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const editor = read('entry/src/main/ets/components/BookmarkEditor.ets');
const gallery = read('entry/src/main/ets/components/GalleryScenes.ets');
const galleryContent = read('entry/src/main/ets/components/GalleryListContent.ets');
const bookmarkScenes = read('entry/src/main/ets/components/GalleryBookmarkScenes.ets');
const panel = read('entry/src/main/ets/components/GallerySearchScenes.ets');
const url = read('entry/src/main/ets/services/EhUrl.ets');
const defaultFlags = Function('return ' + url.match(/DEFAULT_ADVANCE_SEARCH: number = ([^;]+);/)[1])();

// Execute the real UI-independent method bodies; ArkUI rendering is checked by the HAP build.
function bodyOf(source, signature) {
  const method = source.indexOf(signature);
  assert.ok(method >= 0, signature);
  const start = source.indexOf('{', method);
  let depth = 1;
  let end = start + 1;
  for (; end < source.length && depth > 0; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(start + 1, end - 1);
}
const initialize = Function('DEFAULT_ADVANCE_SEARCH', bodyOf(editor, 'aboutToAppear(): void'));
const save = Function(bodyOf(editor, 'private save(): void'));

function bookmark(overrides = {}) {
  return {
    id: 'existing-bookmark', name: 'My bookmark', mode: 0, category: -1, keyword: 'original',
    advanceSearch: 0x407, minRating: 4, pageFrom: 12, pageTo: 80,
    filterEnabled: true, location: 'home', time: 123456,
    ...overrides
  };
}

function open(original) {
  const state = { bookmark: original, saved: [], onSave(value) { this.saved.push(value); } };
  initialize.call(state, defaultFlags);
  return state;
}

test('bookmark options initialize from the saved bookmark, not current search settings', () => {
  const original = bookmark();
  const state = open(original);
  assert.equal(state.advancedEnabledDraft, true);
  assert.equal(state.flagsDraft, original.advanceSearch);
  assert.equal(state.minRatingDraft, original.minRating);
  assert.equal(state.pageFromDraft, original.pageFrom);
  assert.equal(state.pageToDraft, original.pageTo);
  save.call(state);
  assert.deepEqual(state.saved[0], original);
});

test('saving edits every search option while preserving bookmark identity and order', () => {
  const original = Object.freeze(bookmark());
  const state = open(original);
  Object.assign(state, {
    nameDraft: '  Updated  ', keywordDraft: 'new keyword', modeDraft: 3, categoryDraft: 4,
    flagsDraft: 0x15, minRatingDraft: 3, pageFromDraft: 20, pageToDraft: 100,
    filterEnabledDraft: false
  });
  save.call(state);
  assert.deepEqual(state.saved[0], {
    ...original, name: 'Updated', keyword: 'new keyword', mode: 3, category: 4,
    advanceSearch: 0x15, minRating: 3, pageFrom: 20, pageTo: 100, filterEnabled: false
  });
  assert.equal(original.keyword, 'original');
});

test('canceling does not mutate or persist the bookmark; reopening discards the draft', () => {
  const original = Object.freeze(bookmark());
  const state = open(original);
  state.keywordDraft = 'discarded';
  state.flagsDraft = 0;
  assert.deepEqual(state.saved, []);
  const reopened = open(original);
  assert.equal(reopened.keywordDraft, original.keyword);
  assert.equal(reopened.flagsDraft, original.advanceSearch);
  assert.match(editor, /onClick\(\(\) => this\.onCancel\(\)\)/);
});

test('disabling advanced search clears persisted limits, but toggling back retains draft choices', () => {
  const state = open(bookmark());
  state.advancedEnabledDraft = false;
  save.call(state);
  for (const key of ['advanceSearch', 'minRating', 'pageFrom', 'pageTo']) {
    assert.equal(state.saved[0][key], -1);
  }
  assert.equal(open(state.saved[0]).advancedEnabledDraft, false);
  state.advancedEnabledDraft = true;
  save.call(state);
  assert.deepEqual(state.saved[1], bookmark());
});

test('disabled and legacy rating-only bookmarks do not turn the -1 sentinel into all flags', () => {
  const state = open(bookmark({ advanceSearch: -1, minRating: -1, pageFrom: -1, pageTo: -1 }));
  assert.equal(state.advancedEnabledDraft, false);
  assert.equal(state.flagsDraft, defaultFlags);
  state.advancedEnabledDraft = true;
  save.call(state);
  assert.equal(state.saved[0].advanceSearch, defaultFlags);
  const legacy = open(bookmark({ advanceSearch: -1, minRating: 4, pageFrom: -1, pageTo: -1 }));
  assert.equal(legacy.advancedEnabledDraft, true);
  assert.equal(legacy.flagsDraft, defaultFlags);
});

test('bookmark editor reuses search options with one outer scroll and remains above the divider', () => {
  assert.match(editor, /SearchAdvancedPanel\(\{\s*embedded: true/);
  assert.match(panel, /if \(this\.embedded\) \{\s*this\.optionsContent\(\)/);
  assert.match(panel, /Scroll\(\) \{\s*this\.optionsContent\(\)/);
  assert.equal((editor.match(/Scroll\(/g) || []).length, 1);
  assert.match(gallery, /onSave: \(bookmark: SearchBookmarkInfo\) => \{ this\.confirmAddBookmark\(bookmark\); \}/);
  assert.match(gallery, /dividerVisible: this\.useSplitLayout\(\) && !this\.addBookmarkDialogVisible/);
  assert.doesNotMatch(bodyOf(gallery, 'private openEditBookmarkDialog('), /showBookmarkManager = false/);
});

test('page limits are wired through search UI to request parameters', () => {
  for (const field of ['pageFrom', 'pageTo']) {
    const handler = 'on' + field[0].toUpperCase() + field.slice(1) + 'Change';
    assert.ok(editor.includes(`${handler}: (value: number) => { this.${field}Draft = value; }`));
    assert.ok(galleryContent.includes(`${handler}: this.${handler}`));
    assert.ok(gallery.includes(`builder.${field} = this.${field};`));
    assert.ok(galleryContent.includes(`${field}: this.${field}`));
  }
  assert.ok(url.includes("key: 'f_spf'"));
  assert.ok(url.includes("key: 'f_spt'"));
});

test('mounted bookmark rows observe replacements and actions use the updated bookmark', () => {
  const manager = bookmarkScenes.slice(bookmarkScenes.indexOf('export struct SearchBookmarkManagerScene'));
  const rowBody = bodyOf(manager, 'SidePanelEditableManagerRow(').replaceAll('(name: string)', '(name)');
  const bindRow = Function('item', 'index', 'bookmarkSummary', 'return ({' + rowBody + '});');
  const original = bookmark();
  const current = { ...original, name: 'Updated name', keyword: 'new query', advanceSearch: 0x15 };
  const selected = [];
  const state = {
    bookmarks: [original], editingBookmarkId: '',
    onEdit(value) { selected.push(value); }, onRename(value) { selected.push(value); },
    onDelete(value) { selected.push(value); }
  };
  const summary = (value) => value.keyword + ':' + value.advanceSearch;
  const mountedRow = bindRow.call(state, original, 0, summary);
  state.bookmarks = [current]; // Store.getItems() returns a replacement array after Save.
  const updatedRow = bindRow.call(state, original, 0, summary);
  assert.equal(updatedRow.value, current.name);
  assert.equal(updatedRow.subtitle, summary(current));
  // ArkUI can retain the original callback; it must not retain the original data object.
  mountedRow.onEdit();
  mountedRow.onCommit('renamed');
  mountedRow.onDelete();
  assert.deepEqual(selected, [current, current, current]);
  assert.match(manager, /value: this\.bookmarks\[index\]\.name/);
  assert.match(manager, /subtitle: bookmarkSummary\(this\.bookmarks\[index\]\)/);
  assert.match(manager, /item\.id \+ ':' \+ index\.toString\(\)/);
});

test('mounted bookmark drawer forwards current data through a reactive row property', () => {
  const drawer = bookmarkScenes.slice(bookmarkScenes.indexOf('export struct SearchBookmarkDrawer {'),
    bookmarkScenes.indexOf('export struct SearchBookmarkDrawerRow'));
  const bindRow = Function('item', 'index', 'return ({' + bodyOf(drawer, 'SearchBookmarkDrawerRow(') + '});');
  const original = bookmark();
  const updated = { ...original, name: 'Updated', keyword: 'latest query', minRating: 5 };
  const selections = [];
  const state = { bookmarks: [original], onSelect(value) { selections.push(value); } };
  const mounted = bindRow.call(state, original, 0);
  state.bookmarks = [updated];
  assert.equal(bindRow.call(state, original, 0).item, updated);
  mounted.onTap();
  assert.deepEqual(selections, [updated]);
  assert.match(bookmarkScenes, /export struct SearchBookmarkDrawerRow \{\s*@Prop item: SearchBookmarkInfo/);
});

test('all text inputs have the shared search background, never transparent system material', () => {
  const base = new URL('../entry/src/main/ets/components/', import.meta.url);
  let count = 0;
  for (const file of readdirSync(base, { recursive: true }).filter((file) => file.endsWith('.ets'))) {
    const source = readFileSync(new URL(file.replaceAll('\\', '/'), base), 'utf8');
    for (const match of source.matchAll(/Text(?:Input|Area)\([\s\S]*?\.onChange/g)) {
      count++;
      assert.doesNotMatch(match[0], /systemMaterial|backgroundColor\(uiMaterialBackground/, file);
      if (match[0].includes('text: this.searchInputText()')) {
        // Selected tag chips and editor share a single capsule supplied by the parent Row.
        const searchRow = bodyOf(source, 'private searchKeywordEditor()');
        assert.match(searchRow, /\.backgroundColor\(themeFieldBackground\(\)\)/);
      } else {
        assert.match(match[0], /\.backgroundColor\(themeFieldBackground\(\)\)/, file);
      }
    }
  }
  assert.ok(count >= 34, 'the audit must cover the whole application');
});

test('legacy bookmarks are normalized and persisted on first launch after the update', () => {
  const store = read('entry/src/main/ets/services/EhBookmarkStore.ets');
  const normalize = bodyOf(store, 'function normalizeBookmark(');
  assert.match(normalize, /normalizeSubmittedSearchKeywordValue\(sourceKeyword\)/);
  const load = bodyOf(store, 'private async load(');
  assert.match(load, /LEGACY_KEYWORD_MIGRATION_KEY/);
  assert.match(load, /saveSnapshot\(context, normalizedSnapshot\)/);
  const importer = read('entry/src/main/ets/services/AndroidDataImporter.ets');
  assert.match(importer, /normalizeSubmittedSearchKeywordValue\(sourceKeyword\)/);
});

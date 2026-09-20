import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const download = read('components/DownloadScene.ets');
const detailTags = read('components/detail/DetailTags.ets');

function block(source, signature) {
  const index = source.indexOf(signature);
  assert.ok(index >= 0, signature);
  const start = signature.endsWith('{') ? index + signature.length - 1 : source.indexOf('{', index);
  let depth = 1;
  let end = start + 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  return source.slice(start + 1, end - 1);
}

function selectionModel() {
  const state = {
    selectedDownloadGids: '',
    downloadActionsExpanded: false,
    statusText: '',
    visibleItems: []
  };
  for (const name of ['selectedKey', 'downloadSelectionCount', 'isDownloadSelected',
    'toggleDownloadSelection', 'selectAllVisibleDownloads']) {
    state[name] = Function('gid', block(download, 'private ' + name + '(')).bind(state);
  }
  return state;
}

test('select all selects every visible download regardless of state', () => {
  const state = selectionModel();
  state.visibleItems = [
    { gid: 11, state: 'finish' },
    { gid: 22, state: 'downloading' },
    { gid: 33, state: 'wait' },
    { gid: 44, state: 'finish' }
  ];
  state.selectAllVisibleDownloads();
  assert.equal(state.downloadSelectionCount(), 4);
  for (const gid of [11, 22, 33, 44]) {
    assert.equal(state.isDownloadSelected(gid), true, 'gid ' + gid);
  }
  assert.equal(state.downloadActionsExpanded, true);
  assert.match(state.statusText, /Selected 4 /);
});

test('select all replaces an existing partial selection', () => {
  const state = selectionModel();
  state.visibleItems = [{ gid: 5 }, { gid: 6 }, { gid: 7 }];
  state.toggleDownloadSelection(6);
  assert.equal(state.downloadSelectionCount(), 1);
  state.selectAllVisibleDownloads();
  assert.equal(state.downloadSelectionCount(), 3);
  assert.equal(state.isDownloadSelected(5), true);
  assert.equal(state.isDownloadSelected(6), true);
  assert.equal(state.isDownloadSelected(7), true);
});

test('toggling off keeps the remaining keys when selection came from select all', () => {
  const state = selectionModel();
  state.visibleItems = [{ gid: 101 }, { gid: 202 }, { gid: 303 }];
  state.selectAllVisibleDownloads();
  state.toggleDownloadSelection(202);
  assert.equal(state.downloadSelectionCount(), 2);
  assert.equal(state.isDownloadSelected(101), true);
  assert.equal(state.isDownloadSelected(202), false);
  assert.equal(state.isDownloadSelected(303), true);
  state.toggleDownloadSelection(101);
  state.toggleDownloadSelection(303);
  assert.equal(state.downloadSelectionCount(), 0);
  assert.equal(state.selectedDownloadGids, '');
});

test('select all with an empty list keeps the previous selection and reports nothing to select', () => {
  const state = selectionModel();
  state.toggleDownloadSelection(9);
  state.visibleItems = [];
  state.selectAllVisibleDownloads();
  assert.equal(state.downloadSelectionCount(), 1);
  assert.equal(state.isDownloadSelected(9), true);
  assert.match(state.statusText, /No downloads to select/);
});

test('detail tag chips avoid per-chip system material and background blur', () => {
  const row = block(detailTags, 'export struct TagGroupRow');
  const chipStart = row.indexOf('Button({ type: ButtonType.Normal, stateEffect: true })');
  assert.ok(chipStart >= 0, 'tag chip button');
  const chipEnd = row.indexOf('.onClick(', chipStart);
  assert.ok(chipEnd > chipStart, 'tag chip click');
  const chip = row.slice(chipStart, chipEnd);
  assert.match(chip, /\.backgroundColor\(this\.tagBackgroundColor\(\)\)/);
  assert.doesNotMatch(chip, /\.systemMaterial\(/);
  assert.doesNotMatch(chip, /\.backgroundEffect\(/);
});

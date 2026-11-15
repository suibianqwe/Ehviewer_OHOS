import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const windows = read('services/EhWindowImmersive.ets');
const scene = read('components/ReaderScenes.ets');
function erase(code) {
  return code.replace(/\bexport |\bprivate /g, '')
    .replace(/ as number/g, '')
    .replace(/: (?:Promise<void>|window\.Orientation \| undefined|window\.Window|number|boolean|void|string)/g, '');
}
function windowFunction(name) {
  const start = windows.search(new RegExp('^export (?:async )?function ' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(windows.slice(start, windows.indexOf('\n}', start) + 2));
}
function sceneMethod(name) {
  const start = scene.search(new RegExp('^  (?:private )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(scene.slice(start, scene.indexOf('\n  }', start) + 4));
}

test('autoplay keeps its window awake across chrome/foreground refreshes and restores the configured policy on stop', async () => {
  const noop = async () => {};
  const helpers = {
    readerAutoPlaybackWindows: new Set(), logWindowError() {}, rememberWindowPreferredOrientation() {},
    async setWindowKeepScreenOnQuietly(target, value) { target.values.push(value); },
    setPreferredOrientationQuietly: noop, setWindowLayoutFullScreenQuietly: noop,
    setWindowSystemBarEnableQuietly: noop, setSpecificSystemBarEnabledQuietly: noop,
    setWindowSystemBarPropertiesQuietly: noop, setStatusBarContentColorQuietly: noop,
    restoreWindowPreferredOrientation: noop, restoreAppWindowChrome: noop,
    themeTransparentColor: () => '#00000000', HIDDEN_SYSTEM_BARS: [], READER_STATUS_BAR_VISIBLE_SYSTEM_BARS: ['status']
  };
  const api = Function(...Object.keys(helpers),
    ['setReaderAutoPlaybackActive', 'applyReaderWindowState', 'restoreAppWindowState'].map(windowFunction).join('\n') +
    ';return {setReaderAutoPlaybackActive,applyReaderWindowState,restoreAppWindowState};')(...Object.values(helpers));
  const win = id => ({ values: [], getWindowProperties: () => ({ id }) });
  const embedded = win(1), independent = win(2);
  api.setReaderAutoPlaybackActive(embedded, true);
  await api.applyReaderWindowState(embedded, false);
  await api.applyReaderWindowState(embedded, false); // Delayed chrome refresh.
  await api.applyReaderWindowState(independent, false);
  assert.deepEqual(embedded.values, [true, true]);
  assert.deepEqual(independent.values, [false]);
  api.setReaderAutoPlaybackActive(embedded, false);
  await api.applyReaderWindowState(embedded, false);
  assert.equal(embedded.values.at(-1), false);
  api.setReaderAutoPlaybackActive(independent, true);
  await api.applyReaderWindowState(independent, false);
  api.setReaderAutoPlaybackActive(independent, false);
  await api.applyReaderWindowState(independent, true);
  assert.equal(independent.values.at(-1), true, 'explicit keep-screen-on remains effective after playback stops');
  api.setReaderAutoPlaybackActive(independent, true);
  await api.restoreAppWindowState(independent);
  await api.applyReaderWindowState(independent, false);
  assert.deepEqual(independent.values.slice(-2), [false, false]);
  assert.equal(helpers.readerAutoPlaybackWindows.size, 0);
});

test('start, pause, final page and invalid intervals all update the awake policy through the watched playback state', () => {
  const state = Function('setTimeout', 'return {' + ['onAutoTransferPlayingChange', 'scheduleAutoTransfer',
    'startAutoTransferPlayback', 'stopAutoTransferPlayback'].map(sceneMethod).join(',\n') + '};')(() => 42);
  let playing = false;
  const changes = [];
  Object.assign(state, {
    readerWindowActive: true, next: true, delay: 5000,
    applyReaderWindowSettings() { changes.push(this.autoTransferPlaying); },
    canGoNext() { return this.next; }, autoTransferDelayMs() { return this.delay; },
    clearAutoTransferTimer() {}, hideSlider() {}
  });
  Object.defineProperty(state, 'autoTransferPlaying', { get: () => playing, set(value) {
    if (value === playing) return;
    playing = value;
    state.onAutoTransferPlayingChange();
  } });
  state.startAutoTransferPlayback();
  state.stopAutoTransferPlayback();
  state.startAutoTransferPlayback();
  state.next = false;
  state.scheduleAutoTransfer();
  state.next = true;
  state.startAutoTransferPlayback();
  state.delay = 0;
  state.scheduleAutoTransfer();
  assert.deepEqual(changes, [true, false, true, false, true, false]);
  assert.match(scene, /@Watch\('onAutoTransferPlayingChange'\) autoTransferPlaying/);
  assert.match(scene, /setReaderAutoPlaybackActive\(win, this\.autoTransferPlaying\)/);
  const cleanup = scene.slice(scene.indexOf('private cleanupReaderScene()'), scene.indexOf('private installReaderBackHandler()'));
  assert.match(cleanup, /autoTransferPlaying = false/);
  assert.match(cleanup, /setReaderAutoPlaybackActive\(win, false\)/);
});

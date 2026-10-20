import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const support = read('services/ReaderImageAdjustmentSupport.ets');
const service = read('services/ReaderImageAdjustmentService.ets');
const preset = read('services/ReaderPresetSupport.ets');
const erase = text => text.replace(/\b(?:export|private) /g, '')
  .replace(/: Promise<(?:image.PixelMap(?: \| undefined)?|number)>/g, '')
  .replace(/: (?:image.PixelMap|image.ImageSource|ReaderImageAdjustmentSettings|AdjustmentEntry|number|string|boolean)\b(?: \| undefined)?/g, '');
function method(source, name) {
  const start = source.search(new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n  }', start) + 4));
}
function func(source, name) {
  const start = source.indexOf('function ' + name + '(');
  assert.ok(start >= 0, name);
  return erase(source.slice(start, source.indexOf('\n}', start) + 2));
}
const Settings = Function(erase(support.slice(support.indexOf('export class '),
  support.indexOf('const IDENTITY_COLOR_MATRIX'))) + '\nreturn ReaderImageAdjustmentSettings;')();

test('old preset fields are discarded without losing supported image adjustments', () => {
  const parse = Function('ReaderImageAdjustmentSettings', func(preset, 'storedNumber') + '\n' +
    func(preset, 'parseStoredImageAdjustment') + '\nreturn parseStoredImageAdjustment;')(Settings);
  const stored = { enabled: true, contrast: 27, clarity: 12, sharpening: 34, highlights: -20,
    shadows: 15, vibrance: 60, exposure: 7, obsoleteMode: 'High' };
  const restored = parse(JSON.parse(JSON.stringify(stored)));
  for (const key of Object.keys(stored).filter(key => key !== 'obsoleteMode')) {
    assert.equal(restored[key], stored[key], key);
  }
  assert.equal(Object.hasOwn(restored, 'obsoleteMode'), false);
  assert.equal(restored.requiresOfflineProcessing(), true);
  assert.equal(restored.hasColorAdjustments(), true);
  assert.equal(parse(undefined).requiresOfflineProcessing(), false);
});

test('disabled adjustments and display-only color filters do not start native image work', async () => {
  const acquire = Function('return {' + method(service, 'acquire') + '}.acquire;')();
  const state = { acquireEntry() { assert.fail('unnecessary decode/native adjustment'); } };
  const settings = new Settings();
  settings.clarity = 100;
  assert.equal(await acquire.call(state, 'page', '/page.webp', settings), undefined);
  settings.enabled = true;
  settings.clarity = 0;
  settings.contrast = 30;
  assert.equal(settings.requiresOfflineProcessing(), false);
  assert.equal(settings.hasColorAdjustments(), true);
  assert.equal(await acquire.call(state, 'page', '/page.webp', settings), undefined);
});

test('baked and display adjustments preserve all twelve native parameter positions', async () => {
  for (const baked of [false, true]) {
    const settings = new Settings();
    settings.enabled = true;
    const keys = ['contrast', 'clarity', 'sharpening', 'exposure', 'brightness', 'highlights',
      'shadows', 'hue', 'saturation', 'vibrance', 'temperature', 'grayscale'];
    keys.forEach((key, index) => { settings[key] = index + 1; });
    const calls = [];
    let sourceReleased = 0;
    const pixelMap = { getImageInfoSync: () => ({ pixelFormat: 3 }) };
    const native = { async adjustPixelMap(...args) { calls.push(args); return 0; } };
    const image = { PixelMapFormat: { RGBA_8888: 3 }, DecodingDynamicRange: { SDR: 0 },
      createImageSource() { return { getImageInfoSync: () => ({ mimeType: 'image/webp' }),
        getFrameCount: async () => 1, createPixelMap: async () => pixelMap,
        async release() { sourceReleased++; } }; } };
    const create = Function('readerHdr', 'image', 'hilog', 'DOMAIN', 'TAG',
      'return {' + method(service, 'createAdjustedPixelMap') + '}.createAdjustedPixelMap;')(
        native, image, { warn() {} }, 0, 'test');
    const state = { isActive: () => true, releasePixelMap() { assert.fail('returned map released'); } };
    const entry = { settings, sourcePath: '/page.webp', bakeColorAdjustments: baked };
    assert.equal(await create.call(state, entry), pixelMap);
    assert.deepEqual(calls[0], [pixelMap, ...(baked ? keys.map(key => settings[key]) :
      [0, 2, 3, 0, 0, 6, 7, 0, 0, 10, 0, 0])]);
    assert.equal(sourceReleased, 1);
  }
});

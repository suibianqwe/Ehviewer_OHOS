import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const style = read('shared/EhUiStyle.ets');
const functions = style.slice(style.indexOf('export function uiReaderTranslationButtonBackground('),
  style.indexOf('export function uiReaderOptionControlBackground('))
  .replaceAll('export ', '')
  .replace(/: (?:boolean|string|BackgroundEffectOptions \| undefined)/g, '');

function palette(harmony, backgroundEffectSupported, dark) {
  return Function('isHarmonyUiStyle', 'supportsBackgroundEffect', 'materialColorWithAlpha', 'AdaptiveColor', 'isDarkTheme',
    functions + '\nreturn { background: uiReaderTranslationButtonBackground, effect: uiReaderTranslationButtonBackgroundEffect };')(
    () => harmony, () => backgroundEffectSupported,
    (color, alpha) => '#' + alpha + color.slice(1), { DEFAULT: 0 }, () => dark);
}

function whiteContrast(color, background) {
  const value = color.slice(1);
  const alpha = value.length === 8 ? parseInt(value.slice(0, 2), 16) / 255 : 1;
  const rgb = value.slice(-6).match(/../g).map(x => parseInt(x, 16));
  const linear = rgb.map(x => {
    const c = (alpha * x + (1 - alpha) * background) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 1.05 / (0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2] + 0.05);
}

test('reader translation button is 50% transparent in both themes, with and without blur', () => {
  for (const harmony of [false, true]) {
    for (const supported of [false, true]) {
      for (const active of [false, true]) {
        for (const dark of [false, true]) {
          const ui = palette(harmony, supported, dark);
          const effect = ui.effect(active);
          assert.equal(effect !== undefined, harmony && supported);
          const color = effect?.color ?? ui.background(active);
          assert.equal(color.slice(1, 3), '80', '50% opacity means 50% transparency in both themes');
          assert.ok(whiteContrast(color, 0) >= 4.5, 'opaque white symbol remains visible on the black reader margin');
          if (effect) {
            assert.equal(effect.radius, 12);
            assert.equal(ui.background(active), 'rgba(0,0,0,0)');
          }
        }
      }
    }
  }
});

test('floating translation button does not inherit light-theme text or fade the whole control', () => {
  const scene = read('components/ReaderScenes.ets');
  const button = scene.slice(scene.indexOf('if (this.comicTranslationButtonVisible) {'),
    scene.indexOf('.accessibilityText(uiText(\'Comic translation\'))'));
  assert.match(button, /\.fontColor\(\[Color.White\]\)/);
  // SymbolGlyph's generic shadow follows its rectangular bounds, producing a
  // visible square on device. Only the circular button may have a shadow.
  const glyph = button.slice(button.indexOf('SymbolGlyph('), button.indexOf('.width(READER_TRANSLATION_BUTTON_SIZE)'));
  assert.doesNotMatch(glyph, /\.shadow\(/);
  assert.match(button, /uiReaderTranslationButtonBackground\(this.comicTranslationActive\)/);
  assert.match(button, /uiReaderTranslationButtonBackgroundEffect\(this.comicTranslationActive\)/);
  assert.doesNotMatch(button, /uiMaterialForegroundColor|uiMaterialBackground|\.systemMaterial|\.opacity/);
});

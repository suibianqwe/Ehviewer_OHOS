import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const source = read('services/ReaderAnimationPlayback.ets');
const Playback = Function(source.replace('@Observed', '').replace(/\bexport /g, '')
  .replace(/: (?:number|boolean|void)\b/g, '') + '\nreturn ReaderAnimationPlayback;')();

test('unknown and animated offscreen pages do not mount an Image decoder', () => {
  const player = new Playback();
  assert.equal(player.shouldMountImage(false), false);
  assert.equal(player.shouldMountImage(true), true);
  for (const count of [2, 50, 155, 182]) {
    player.classify(count);
    assert.equal(player.shouldMountImage(false), false);
    assert.equal(player.shouldMountImage(true), true);
  }
});

test('static images keep offscreen pre-rendering; reset cannot reuse old classification', () => {
  const player = new Playback();
  player.classify(1);
  assert.equal(player.shouldMountImage(false), true);
  player.reset();
  assert.equal(player.frameCount, 0);
  assert.equal(player.shouldMountImage(false), false);
});

test('many cached animated pages mount only the visible page or spread', () => {
  const players = Array.from({ length: 20 }, () => new Playback());
  players.forEach(p => p.classify(120));
  const mounted = visible => players.filter((p, i) => p.shouldMountImage(visible.includes(i))).length;
  assert.equal(mounted([0]), 1);
  assert.equal(mounted([5, 6]), 2);
  assert.equal(mounted([]), 0);
});

test('both reader modes gate only the image node, preserving layout, static pre-render and quality', () => {
  const viewport = read('components/reader/viewports/ReaderImageViewport.ets');
  const continuous = read('components/reader/viewports/ReaderContinuousImageItem.ets');
  assert.match(viewport, /shouldMountImage\(this\.isActive &&\s*\(this\.imageInViewport \|\| this\.prepareForPresentation\)\)/);
  const spread = read('components/reader/viewports/ReaderSpreadViewport.ets');
  assert.match(spread, /prepareForPresentation: offset === 1 && this\.preparedSecond/);
  assert.match(spread, /this\.preparedSecond = false/);
  assert.match(continuous, /shouldMountImage\(this\.imageInViewport\)/);
  for (const code of [viewport, continuous]) {
    assert.match(code, /animationPlayback\.reset\(\)/);
    assert.match(code, /if \(requestId !== this\.sourceSizeRequestId \|\| imageUrl !== this\.imageUrl\(\)\) \{\n      return;\n    }\n    this\.animationPlayback\.classify/);
    assert.match(code, /onVisibleAreaChange\(\[0\.0\]/);
    assert.match(code, /if \(this\.displayPixelMap\(\) !== undefined \|\|/);
    assert.match(code, /interpolation\(this\.isActive \? ImageInterpolation\.High : ImageInterpolation\.Low\)/);
    assert.match(code, /onComplete\(\(event\?: ReaderImageCompleteEvent\) => this\.onImageComplete\(event\)\)/);
    assert.doesNotMatch(code, /AnimatedDrawableDescriptor|animationPlayback\.source|syncAnimationPlayback/);
  }
  const core = read('components/reader/core/ReaderCore.ets');
  assert.match(core, /await imageSource\.getImageInfo\(\)/);
  assert.match(core, /await imageSource\.getFrameCount\(\)/);
  assert.doesNotMatch(source, /createPixelMapList|createPixelMap\(|createPixelMapSync|AnimatedDrawableDescriptor|setTimeout/);
});

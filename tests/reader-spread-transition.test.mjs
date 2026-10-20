import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const erase = text => text.replace(/@Observed\n/g, '').replace(/\b(?:export|private) /g, '')
  .replace(/: (?:ReaderSpreadGeometry|ReaderSpreadMotion|number|string|boolean|void)\b/g, '');
const logic = read('services/ReaderSpreadTransition.ets').replace(/export interface ReaderSpreadGeometry \{[^}]+\}/, '');
const { readerSpreadGeometry: geometry, ReaderSpreadMotion: Motion } = Function(erase(logic) +
  ';return {readerSpreadGeometry, ReaderSpreadMotion};')();
const viewport = read('components/reader/viewports/ReaderSpreadViewport.ets');
function method(name) {
  const start = viewport.search(new RegExp('^  (?:private )?' + name + '\\(', 'm'));
  assert.ok(start >= 0, name);
  return erase(viewport.slice(start, viewport.indexOf('\n  }', start) + 4));
}
const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.00001, `${actual} != ${expected}`);

for (const reversed of [false, true]) {
  test('incoming page joins from ' + (reversed ? 'left' : 'right') + ' before both images center', () => {
    const g = geometry(1600, 1000, 700, 1000, 600, 1000, reversed);
    assert.equal(Math.sign(g.outsideX), reversed ? -1 : 1);
    assert.ok(Math.abs(g.outsideX) >= 1600);
    near(g.joinX, (reversed ? -1 : 1) * 650);
    const firstLeft = g.firstX - 700 * g.scale / 2;
    const firstRight = g.firstX + 700 * g.scale / 2;
    const secondLeft = g.secondX - 600 * g.scale / 2;
    const secondRight = g.secondX + 600 * g.scale / 2;
    near(reversed ? secondRight : firstRight, reversed ? firstLeft : secondLeft);
    near(Math.min(firstLeft, secondLeft) + Math.max(firstRight, secondRight), 0);
    const m = new Motion(); m.prepare(g);
    assert.equal(m.firstX, 0); assert.equal(m.scale, 1);
    m.join(g); assert.equal(m.firstX, 0); assert.equal(m.scale, 1);
    m.settle(g); assert.equal(m.scale, g.scale);
    m.finish(); assert.equal(m.phase, 'paired');
  });
}

test('fitting an oversized spread keeps its seam joined throughout common scaling and translation', () => {
  const g = geometry(1200, 1000, 650, 1000, 650, 1000, false);
  assert.ok(g.scale < 1);
  for (let step = 0; step <= 10; step++) {
    const t = step / 10;
    const scale = 1 + (g.scale - 1) * t;
    const firstX = g.firstX * t;
    const secondX = g.joinX + (g.secondX - g.joinX) * t;
    near(firstX + 650 * scale / 2, secondX - 650 * scale / 2);
  }
});

test('portrait spreads and non-centered start positions end at the same correct centered canvas', () => {
  const g = geometry(1000, 1500, 1000, 700, 1000, 600, false, 'Top left');
  near(g.joinY + (1500 - 600) * -0.5, (1500 - 700) * -0.5 + 650);
  near(g.firstY + (1500 - 700) * -0.5 * g.scale, -300 * g.scale);
  near(g.secondY + (1500 - 600) * -0.5 * g.scale, 350 * g.scale);
  const h = geometry(1600, 1000, 700, 1000, 600, 1000, true, 'Bottom right');
  near(h.firstX + (1600 - 700) * 0.5 * h.scale, 300 * h.scale);
  near(h.secondX + (1600 - 600) * 0.5 * h.scale, -350 * h.scale);
});

function component(immediateAnimations = false) {
  const timers = new Map(); const animations = []; const presentations = []; let next = 0;
  const names = ['aboutToAppear', 'aboutToDisappear', 'geometry', 'cancelMotion', 'onLayoutChange',
    'onImageReady', 'onImageFailed', 'startArrivalWhenReady', 'isCurrent', 'firstInteractive'];
  const state = Function('readerSpreadGeometry', 'normalizeStartPositionOption', 'setTimeout', 'clearTimeout', 'Curve', 'hilog',
    'return {' + names.map(method).join(',') + '};')(geometry, s => s,
      fn => { timers.set(++next, fn); return next; }, id => timers.delete(id), { EaseOut: 0, EaseInOut: 1 }, { info() {} });
  Object.assign(state, { viewportWidth: 1600, viewportHeight: 1000, firstWidth: 700, firstHeight: 1000,
    secondWidth: 600, secondHeight: 1000, reversed: false, paired: false, isActive: true, startPosition: 'Center',
    motion: new Motion(), preparedSecond: false, pairedReady: false, mounted: false,
    firstReady: false, secondReady: false, wasPaired: false, layoutSignature: '', revision: 0, startTimer: -1,
    onPresentationChange(ready, animating) { presentations.push({ ready, animating }); },
    getUIContext() { return { animateTo(options, apply) {
      apply(); animations.push({ options, phase: state.motion.phase });
      if (immediateAnimations) options.onFinish();
    } }; }
  });
  state.aboutToAppear();
  const flush = () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); };
  const arrive = () => { state.onImageReady(0, true); state.paired = true; state.onLayoutChange(); };
  return { state, timers, animations, presentations, flush, arrive };
}

test('a visible single page remains intact until the new native image is actually ready', () => {
  const h = component(); h.arrive();
  assert.equal(h.state.motion.phase, 'waiting'); assert.equal(h.state.firstInteractive(), true);
  assert.equal(h.state.motion.firstX, 0); assert.equal(h.state.preparedSecond, true);
  h.state.onImageReady(1, false); h.flush(); assert.equal(h.animations.length, 0);
  h.state.onImageReady(1, true); h.flush();
  assert.equal(h.animations[0].phase, 'joining'); assert.equal(h.state.motion.firstX, 0);
  assert.equal(h.state.firstInteractive(), false);
  h.animations[0].options.onFinish();
  assert.equal(h.animations[1].phase, 'settling'); assert.equal(h.state.pairedReady, false);
  h.animations[1].options.onFinish();
  assert.equal(h.state.pairedReady, true); assert.equal(h.state.preparedSecond, false);
  assert.deepEqual(h.presentations.at(-1), { ready: true, animating: false });
});

test('known spreads mount directly; background caches do not start visible arrival animations', () => {
  const h = component(); h.state.paired = true; h.state.onLayoutChange();
  assert.equal(h.state.motion.phase, 'paired'); assert.equal(h.animations.length, 0);
  const inactive = component(); inactive.state.isActive = false; inactive.arrive();
  inactive.state.onImageReady(1, true); inactive.flush();
  assert.equal(inactive.animations.length, 0); assert.equal(inactive.state.preparedSecond, false);
});

test('exit, rotation, direction changes and navigation invalidate old animation callbacks', () => {
  for (const change of [h => h.state.aboutToDisappear(), h => {
    h.state.viewportWidth = 1000; h.state.viewportHeight = 1600; h.state.onLayoutChange();
  }, h => { h.state.reversed = true; h.state.onLayoutChange(); }, h => {
    h.state.isActive = false; h.state.onLayoutChange();
  }]) {
    const h = component(); h.arrive(); h.state.onImageReady(1, true); h.flush();
    const finish = h.animations[0].options.onFinish;
    change(h); const count = h.animations.length;
    finish(); assert.equal(h.animations.length, count);
  }
});

test('a changed source cancels queued arrival; failed incoming images expose retry without replacing the first', () => {
  const h = component(); h.arrive(); h.state.onImageReady(1, true);
  h.state.onImageReady(1, false); h.flush(); assert.equal(h.animations.length, 0);
  h.state.onImageFailed(1);
  assert.equal(h.state.motion.phase, 'paired'); assert.equal(h.state.pairedReady, true);
  assert.equal(h.state.preparedSecond, false);
});

test('disabled system animations complete both phases without deadlocking input', () => {
  const h = component(true); h.arrive(); h.state.onImageReady(1, true); h.flush();
  assert.equal(h.state.motion.phase, 'paired'); assert.equal(h.state.pairedReady, true);
  assert.deepEqual(h.presentations.at(-1), { ready: true, animating: false });
});

test('persistent page call sites use only render transforms, transparent layers and scoped offscreen preparation', () => {
  const scene = read('components/ReaderScenes.ets');
  const image = read('components/reader/viewports/ReaderImageViewport.ets');
  const build = viewport.slice(viewport.indexOf('  build()'));
  assert.equal(build.match(/this\.Page\(0\)/g).length, 1);
  assert.match(build, /if \(this\.paired\) \{\s*Stack\(\) \{ this\.Page\(1\) \}/);
  assert.doesNotMatch(build, /opacity|transition\(|this\.Page\(0\)[\s\S]*else/);
  assert.match(viewport, /transparentBackground: true/);
  assert.match(image, /backgroundColor\(this\.transparentBackground \? Color\.Transparent/);
  assert.match(image, /if \(event\.loadingStatus === 1\) \{\s*this\.onImageReady\(true\)/);
  assert.doesNotMatch(scene, /\? ':paired' : ':single'|paired === this\.shouldPairPage\(index\)/);
  assert.match(scene, /disableSwipe\(this\.isDisableSwipe \|\| this\.pairedJoining\)/);
  assert.match(viewport, /prepareForPresentation: offset === 1 && this\.preparedSecond/);
});

import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const rootPath = fileURLToPath(root);

function read(path) {
  return readFileSync(new URL(path, root), 'utf8');
}

function json5Value(path, key) {
  const match = read(path).match(new RegExp(`"${key}"\\s*:\\s*"([^"]+)"`));
  assert.ok(match, `${path} must define ${key}`);
  return match[1];
}

function etsFiles(directory) {
  const base = new URL(directory, root);
  const paths = [];
  const visit = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        visit(full);
      } else if (entry.name.endsWith('.ets')) {
        paths.push(full);
      }
    }
  };
  visit(fileURLToPath(base));
  return paths;
}

test('release metadata stays synchronized', () => {
  const version = json5Value('AppScope/app.json5', 'versionName');
  assert.equal(json5Value('oh-package.json5', 'version'), version);
  assert.equal(json5Value('entry/oh-package.json5', 'version'), version);
  assert.equal(JSON.parse(read('package.json')).version, version);
  assert.ok(read('README.md').includes('当前版本：`' + version + '`'));
  assert.ok(read('README_EN.md').includes('Current version: `' + version + '`'));
});

test('API 26 system material follows the documented direct-call compatibility path', () => {
  const calls = [];
  for (const path of etsFiles('entry/src/main/ets/')) {
    const source = readFileSync(path, 'utf8');
    if (source.includes('.systemMaterial(')) {
      calls.push(relative(rootPath, path).replaceAll('\\', '/'));
    }
  }
  assert.ok(calls.length > 0, 'interactive components must call systemMaterial directly');
  assert.ok(calls.every((path) => path.includes('/components/')),
    'systemMaterial must stay on the component attribute chain');

  const style = read('entry/src/main/ets/shared/EhUiStyle.ets');
  assert.match(style, /deviceInfo\.sdkApiVersion\s*<\s*26/,
    'material creation must use the API-level gate from the official compatibility guide');
  assert.doesNotMatch(style, /CommonModifier|attributeModifier|SYSTEM_MATERIAL_MODIFIERS/,
    'systemMaterial must not be hidden behind an AttributeModifier');

  const moduleProfile = read('entry/src/main/module.json5');
  assert.match(moduleProfile,
    /"name"\s*:\s*"ohos\.arkui\.UIMaterial\.state"[\s\S]*"value"\s*:\s*"enable"/,
    'the entry module must explicitly enable immersive material');
});

test('versioned web and download features keep explicit fallbacks', () => {
  const web = read('entry/src/main/ets/services/EhWebRuntime.ets');
  assert.match(web, /if \(deviceInfo\.apiAvailable\(24\)\)[\s\S]*setUserAgentMetadata/);
  assert.match(web, /setCustomUserAgent/);

  const download = read('entry/src/main/ets/services/PublicDownloadService.ets');
  assert.match(download,
    /if \(canIUse\('SystemCapability\.Request\.FileTransferAgent'\)\)[\s\S]*request\.agent\.create/);
  assert.match(download,
    /if \(canIUse\('SystemCapability\.MiscServices\.Download'\)\)[\s\S]*request\.downloadFile/);
});

test('large ArkTS units cannot grow without an explicit budget review', () => {
  const budgets = new Map([
    ['entry/src/main/ets/components/GalleryScenes.ets', 2800],
    ['entry/src/main/ets/components/GalleryListContent.ets', 2400],
    ['entry/src/main/ets/components/GalleryListSupport.ets', 500],
    ['entry/src/main/ets/components/GalleryBookmarkScenes.ets', 750],
    ['entry/src/main/ets/components/GalleryOverlayComponents.ets', 550],
    ['entry/src/main/ets/components/DownloadScene.ets', 2900],
    ['entry/src/main/ets/components/DownloadComponents.ets', 750],
    ['entry/src/main/ets/shared/EhShared.ets', 2600],
    ['entry/src/main/ets/shared/EhTranslations.ets', 2100],
    ['entry/src/main/ets/components/SettingsScene.ets', 2750],
    ['entry/src/main/ets/components/SettingsSupport.ets', 350],
    ['entry/src/main/ets/components/SettingsPanels.ets', 1000],
    ['entry/src/main/ets/components/SettingsOverlays.ets', 800],
    ['entry/src/main/ets/components/ReaderScenes.ets', 3950],
    ['entry/src/main/ets/components/ReaderSceneSupport.ets', 250],
    ['entry/src/main/ets/services/GalleryFixtures.ets', 350],
    ['entry/src/main/ets/services/GalleryDetailSupport.ets', 550],
    ['entry/src/main/ets/services/TranslationSupport.ets', 400],
    ['entry/src/main/ets/services/EhUrl.ets', 450]
  ]);
  for (const [path, budget] of budgets) {
    const lines = read(path).split(/\r?\n/).length;
    assert.ok(lines <= budget, `${path} has ${lines} lines; budget is ${budget}`);
  }
});

test('warning suppressions document the runtime safety condition', () => {
  for (const path of etsFiles('entry/src/main/ets/')) {
    for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
      if (line.includes('@SuppressWarnings')) {
        assert.match(line, /-- \S/,
          `${path} contains an unexplained warning suppression`);
      }
    }
  }
});

test('reader exit has one window-state owner and defers list state updates', () => {
  const reader = read('entry/src/main/ets/components/ReaderScenes.ets');
  assert.doesNotMatch(reader, /restoreAppWindowStateForReaderExit|restoreSystemBarsForReaderExit/,
    'ReaderScene teardown must not race the parent-owned embedded-reader restore');

  const galleries = read('entry/src/main/ets/components/GalleryListContent.ets');
  assert.match(galleries, /onGalleriesChanged\(\): void \{[\s\S]*this\.translationVisibleStart = -1/);
  assert.match(galleries, /onGalleriesChanged\(\): void \{[\s\S]*this\.translationVisibleEnd = -1/,
    'replacing the gallery list must reset the visible translation range');
});

test('embedded reader hides the dual-pane divider', () => {
  const galleries = read('entry/src/main/ets/components/GalleryScenes.ets');
  assert.match(galleries,
    /if \(\(this\.showDetail \|\| this\.showBookmarkManager\) && !this\.showReader\) \{\s*SplitPaneDivider\(/,
    'the split-pane divider must not render above the embedded reader');
});

test('gallery list keeps a stable edge inset on wide layouts', () => {
  const style = read('entry/src/main/ets/shared/EhUiStyle.ets');
  const galleries = read('entry/src/main/ets/components/GalleryListContent.ets');
  assert.match(galleries,
    /private galleryContentPadding\(\): number \{[\s\S]*galleryListHorizontalPadding/,
    'gallery cards must keep the same 12vp edge inset on wide screens');
  assert.match(galleries,
    /galleryListColumnCount\(width, preferred, gap\)/,
    'gallery column calculation must use the same edge inset as the rendered list');
  assert.match(style,
    /horizontalPadding: number = 0[\s\S]*edgePadding = horizontalPadding > 0 \? horizontalPadding/,
    'adaptive column helper must support a caller-provided edge inset');
});

test('Harmony materials keep visible low-tier fallbacks', () => {
  const style = read('entry/src/main/ets/shared/EhUiStyle.ets');
  assert.doesNotMatch(style, /materialColor:\s*Color\.Transparent/,
    'transparent materialColor becomes a transparent background on low-tier devices');
  assert.doesNotMatch(style, /materialColor:\s*['"]transparent['"]/,
    'neutral materials must let the system choose its tier-specific fallback');
  assert.match(style,
    /uiMaterialLayerBackground[\s\S]*materialColorWithAlpha\(solidColor,[\s\S]*: solidColor/,
    'child layers without their own material must retain a visible background');
  assert.match(style,
    /uiMaterialBackground[\s\S]*return Color\.Transparent/,
    'API 26 material controls must clear backgroundColor so it cannot cover the material filter');
  assert.match(style,
    /uiButtonMaterial[\s\S]*return uiMaterial\.Material\.empty/,
    'ordinary buttons must explicitly opt out of the restricted API 26 system material');
  assert.match(style,
    /uiTintedButtonMaterial[\s\S]*return uiMaterial\.Material\.empty/,
    'tinted buttons must explicitly opt out of the restricted API 26 system material');
  assert.match(style,
    /uiReaderOptionButtonMaterial[\s\S]*return uiMaterial\.Material\.empty/,
    'reader option buttons must use the same component-level material opt-out');
  assert.match(style,
    /uiTransparentButtonBackgroundEffect[\s\S]*radius: 40[\s\S]*rgba\(255,255,255,0\.62\)/,
    'button blur must remain enabled on API 26 and use a light, non-gray tint in light mode');
  assert.doesNotMatch(style,
    /uiTransparentButtonBackgroundEffect\(\)[\s\S]{0,400}isHarmonyMaterialEnabled\(\)/,
    'button blur must not be disabled merely because API 26 system material is available');
  assert.doesNotMatch(style, /uiButtonPressLightEffect|PressShadowType\.BLEND_GRADIENT/,
    'buttons must not retain the obsolete simulated immersive-light path');
  assert.match(style, /uiDialogBlurStyle[\s\S]*isHarmonyUiStyle\(\)[\s\S]*BlurStyle\.BACKGROUND_THICK/,
    'Harmony dialogs must keep an explicit background blur path');
  assert.match(style,
    /uiSearchMaterial[\s\S]*ImmersiveStyle\.THIN[\s\S]*interactive: true[\s\S]*lightEffect:/,
    'supported search controls must retain the API 26 interactive material');
  assert.match(style,
    /uiSegmentMaterial[\s\S]*ImmersiveStyle\.ULTRA_THIN[\s\S]*applyShadow: false[\s\S]*interactive: true[\s\S]*lightEffect:/,
    'segmented controls must retain the light, interactive material used by the working 0.6.7 implementation');
  assert.match(style, /rgba\(.*0\.45\)/,
    'material tint must remain translucent enough for dynamic light feedback to remain visible');

  const searchScenes = read('entry/src/main/ets/components/GallerySearchScenes.ets');
  assert.match(searchScenes,
    /backgroundEffect\(uiFloatingButtonBackgroundEffect\(this\.primary \|\| this\.checked \? themePrimaryColor\(\) : ''\)\)[\s\S]*systemMaterial\(uiTintedButtonMaterial\(this\.buttonColor\(\)\)\)/,
    'floating actions must combine a visible tinted blur with the API 26 material opt-out');

  const readerScenes = read('entry/src/main/ets/components/ReaderScenes.ets');
  assert.match(readerScenes,
    /backgroundEffect\(uiFloatingButtonBackgroundEffect\(this\.comicTranslationActive \? '#167A9A' : '#34454D'\)\)[\s\S]*systemMaterial\(uiTintedButtonMaterial/,
    'the reader translation action must retain its tinted Gaussian blur');

  const readerButtons = read('entry/src/main/ets/components/reader/controls/ReaderButtons.ets');
  assert.match(readerButtons,
    /backgroundEffect\(uiFloatingButtonBackgroundEffect[\s\S]*systemMaterial\(uiTintedButtonMaterial/,
    'reader toolbar buttons must apply the Gaussian blur before disabling system material');

  const holdingHandSupport = read('entry/src/main/ets/services/EhHoldingHandSupport.ets');
  assert.match(holdingHandSupport,
    /getRecentOperatingHandStatus\(\)[\s\S]*holdingHandChanged[\s\S]*operatingHandChanged/,
    'holding-hand adaptation must initialize immediately and keep listening for both grip and operating-hand changes');

  const confirmOverlay = read('entry/src/main/ets/components/ConfirmActionOverlay.ets');
  assert.match(confirmOverlay,
    /backgroundBlurStyle\(uiDialogBlurStyle\(\), uiDialogBlurOptions\(\)\)/,
    'custom confirmation overlays must keep a real background blur');
  assert.match(confirmOverlay,
    /backgroundEffect\(uiTransparentButtonBackgroundEffect\(\)\)[\s\S]*backgroundEffect\(uiFloatingButtonBackgroundEffect/,
    'custom confirmation buttons must use neutral or tinted Gaussian blur');
  assert.doesNotMatch(confirmOverlay, /visualEffect|uiButtonPressLightEffect/,
    'custom confirmation buttons must not simulate immersive light');
});

test('daily check-in uses a cookie-backed background Web and keeps the foreground dialog', () => {
  const index = read('entry/src/main/ets/pages/Index.ets');
  const service = read('entry/src/main/ets/services/EhDailyCheckInService.ets');
  assert.match(index, /Web\(\{ src: '', controller: this\.dailyCheckInWebController, incognitoMode: false \}\)/);
  assert.match(index,
    /prepareDailyCheckInWebCookies\(\)[\s\S]*loadEhWebUrlWithAndroidCompatibility\(this\.dailyCheckInWebController, EhUrl\.getNewsUrl\(\)\)/,
    'saved cookies must be synchronized before news.php is loaded');
  assert.match(index, /syncCookieHeaderToWebView\(EhUrl\.HOST_E, cookieHeader, false\)/);
  assert.match(index, /captureEhAccountWebCookies\(url\)[\s\S]*ehCookieStore\.save\(context\)/,
    'cookies updated by ArkWeb must be persisted back to the app session');
  assert.match(index,
    /if \(result\.event !== null\)[\s\S]*this\.dailyCheckInDialogVisible = true/,
    'a successful daily event must still open the foreground dialog');
  assert.doesNotMatch(service, /EhHttpClient|getText\(/,
    'daily check-in must not bypass ArkWeb with a raw HTTP request');
});

test('search scenes refresh suggestions after async search-history load', () => {
  const galleryScenes = read('entry/src/main/ets/components/GalleryListContent.ets');
  const downloadScene = read('entry/src/main/ets/components/DownloadScene.ets');
  for (const source of [galleryScenes, downloadScene]) {
    assert.match(source,
      /ehSearchHistoryStore\.load\(context\)\.then\(\(\) => \{\s*this\.refreshSearchSuggestions\(\);/,
      'search suggestions must refresh after the persisted history store becomes ready');
  }
});

test('the standard gallery list keeps LazyForEach as a direct child of List', () => {
  const galleries = read('entry/src/main/ets/components/GalleryListContent.ets');
  const standardList = galleries.match(/private galleryStandardList\(\) \{[\s\S]*?\n  \}/);
  assert.ok(standardList, 'galleryStandardList must exist');
  assert.doesNotMatch(standardList[0], /ListItemGroup\(/,
    'wrapping LazyForEach in ListItemGroup hides the group height, so List keeps re-estimating ' +
    'row positions while scrolling and the gallery page jitters');
  assert.match(standardList[0],
    /List\(\{ space: this\.galleryStandardListSpace\(\), scroller: this\.listScroller \}\) \{[\s\S]*LazyForEach\(this\.galleryThumbnailSource/,
    'the lazy gallery items must sit directly under List so each row height can be measured');
});

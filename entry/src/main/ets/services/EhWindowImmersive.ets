import { common } from '@kit.AbilityKit';
import { settings } from '@kit.BasicServicesKit';
import { display, window } from '@kit.ArkUI';
import { ehSettingsStore } from './EhSettingsStore';
import { isDarkTheme, themeSystemBarContentColor, themeTransparentColor } from '../shared/EhTheme';

export const MAIN_WINDOW_KEY: string = 'mainWindow';
export const READER_WINDOW_KEY: string = 'readerWindow';
export const EMBEDDED_READER_ACTIVE_KEY: string = 'embeddedReaderActive';
export const MAIN_CONTENT_WIDTH_VP_KEY: string = 'mainContentWidthVp';
type SystemBarName = 'status' | 'navigation';
type SpecificSystemBarName = 'status' | 'navigationIndicator';

const VISIBLE_SYSTEM_BARS: SystemBarName[] = ['status'];
const HIDDEN_SYSTEM_BARS: SystemBarName[] = [];
const READER_STATUS_BAR_VISIBLE_SYSTEM_BARS: SystemBarName[] = ['status'];
const savedReaderPreferredOrientations: Map<number, window.Orientation> = new Map();
const savedReaderDisplayOrientations: Map<number, display.Orientation> = new Map();
const savedReaderWindowOrientations: Map<number, window.Orientation> = new Map();
const pendingReaderExitOrientations: Map<number, window.Orientation> = new Map();
let readerChromeGeneration: number = 0;

export function rememberMainWindow(win: window.Window): void {
  AppStorage.set<window.Window | undefined>(MAIN_WINDOW_KEY, win);
}

export function getMainWindow(): window.Window | undefined {
  return AppStorage.get<window.Window>(MAIN_WINDOW_KEY);
}

export function rememberMainContentWidthVp(width: number): void {
  const normalized = Math.floor(width);
  if (normalized < 240 || Number.isNaN(normalized)) {
    return;
  }
  AppStorage.setOrCreate<number>(MAIN_CONTENT_WIDTH_VP_KEY, normalized);
}

export function mainContentWidthFallbackVp(pxToVp: (value: number) => number): number {
  const remembered = AppStorage.get<number>(MAIN_CONTENT_WIDTH_VP_KEY);
  if (remembered !== undefined && remembered >= 240) {
    return remembered;
  }
  const win = getMainWindow();
  if (win === undefined) {
    return 0;
  }
  try {
    return normalizeWindowWidthVp(win.getWindowProperties().windowRect.width, pxToVp);
  } catch (_error) {
    return 0;
  }
}

function normalizeWindowWidthVp(rawWidth: number, pxToVp: (value: number) => number): number {
  const raw = Math.floor(rawWidth);
  if (raw <= 0 || Number.isNaN(raw)) {
    return 0;
  }
  const converted = Math.floor(pxToVp(raw));
  if (converted >= 320) {
    return converted;
  }
  if (converted >= 240 && raw > 640) {
    return converted;
  }
  if (raw >= 240 && raw <= 1200) {
    return raw;
  }
  return Math.max(0, converted);
}

export function rememberReaderWindow(win: window.Window): void {
  AppStorage.set<window.Window | undefined>(READER_WINDOW_KEY, win);
}

export function clearReaderWindow(): void {
  AppStorage.set<window.Window | undefined>(READER_WINDOW_KEY, undefined);
}

export function getReaderWindow(): window.Window | undefined {
  return AppStorage.get<window.Window>(READER_WINDOW_KEY);
}

export function setEmbeddedReaderActive(active: boolean): void {
  AppStorage.setOrCreate<boolean>(EMBEDDED_READER_ACTIVE_KEY, active);
}

export function isEmbeddedReaderActive(): boolean {
  return AppStorage.get<boolean>(EMBEDDED_READER_ACTIVE_KEY) === true;
}

// Normal app pages: window-level immersive layout with status bar visible and navigation indicator hidden.
export function applyAppChromeImmersiveMode(win?: window.Window): void {
  const target = win === undefined ? getMainWindow() : win;
  if (target === undefined) {
    return;
  }
  if (isEmbeddedReaderActive()) {
    return;
  }
  applyAppChromeImmersiveModeAsync(target).catch(() => {});
}

export async function prepareAppChromeBeforeContent(win: window.Window): Promise<void> {
  await applyAppChromeImmersiveModeAsync(win);
}

// Reader page only: full-screen layout with both status bar and navigation indicator hidden.
export function applyReaderFullscreenImmersiveMode(win?: window.Window): void {
  const target = win === undefined ? (getReaderWindow() ?? getMainWindow()) : win;
  if (target === undefined) {
    return;
  }
  applyReaderWindowStateFromSettings(target).catch(() => {});
}

export function enterEmbeddedReaderFullscreen(): void {
  readerChromeGeneration++;
  const generation = readerChromeGeneration;
  setEmbeddedReaderActive(true);
  const target = getMainWindow();
  if (target === undefined) {
    return;
  }
  rememberWindowPreferredOrientation(target);
  applyReaderWindowStateFromSettings(target).catch(() => {});
  scheduleReaderFullscreenImmersiveMode(target, 32, generation);
  scheduleReaderFullscreenImmersiveMode(target, 120, generation);
  scheduleReaderFullscreenImmersiveMode(target, 320, generation);
  scheduleReaderFullscreenImmersiveMode(target, 800, generation);
}

export function leaveEmbeddedReaderFullscreen(): Promise<void> {
  readerChromeGeneration++;
  const generation = readerChromeGeneration;
  setEmbeddedReaderActive(false);
  const target = getMainWindow();
  if (target === undefined) {
    return Promise.resolve();
  }
  return restoreAppWindowState(target).then(() => {
    scheduleAppWindowStateAfterReader(target, 32, generation);
    scheduleAppWindowStateAfterReader(target, 120, generation);
    scheduleAppWindowStateAfterReader(target, 320, generation);
    scheduleAppWindowStateAfterReader(target, 800, generation);
    scheduleAppWindowStateAfterReader(target, 1600, generation);
    scheduleAppWindowStateAfterReader(target, 3000, generation);
  }).catch(() => {});
}

function scheduleAppWindowStateAfterReader(win: window.Window, delayMs: number, generation: number): void {
  setTimeout(() => {
    if (isEmbeddedReaderActive() || generation !== readerChromeGeneration) {
      return;
    }
    restoreAppWindowChrome(win).then(() => {
      restorePendingReaderExitOrientation(win).catch(() => {});
    }).catch(() => {});
  }, delayMs);
}

export function scheduleReaderFullscreenImmersiveMode(win: window.Window, delayMs: number): void;
export function scheduleReaderFullscreenImmersiveMode(win: window.Window, delayMs: number, generation: number): void;
export function scheduleReaderFullscreenImmersiveMode(win: window.Window, delayMs: number,
  generation: number = readerChromeGeneration): void {
  setTimeout(() => {
    if (generation !== readerChromeGeneration || (win === getMainWindow() && !isEmbeddedReaderActive())) {
      return;
    }
    applyReaderWindowStateFromSettings(win).catch(() => {});
  }, delayMs);
}

async function applyAppChromeImmersiveModeAsync(target: window.Window): Promise<void> {
  const useLightSystemBarIcons = isDarkTheme();
  await setWindowLayoutFullScreenQuietly(target, true, 'set app full-screen layout');
  await setWindowSystemBarEnableQuietly(target, VISIBLE_SYSTEM_BARS, 'show app system bars');
  await setSpecificSystemBarEnabledQuietly(target, 'status', true, 'show app status bar');
  await setSpecificSystemBarEnabledQuietly(target, 'navigationIndicator', false, 'hide app navigation indicator');
  await setWindowSystemBarPropertiesQuietly(target, {
    statusBarColor: themeTransparentColor(),
    navigationBarColor: themeTransparentColor(),
    isStatusBarLightIcon: useLightSystemBarIcons,
    isNavigationBarLightIcon: useLightSystemBarIcons,
    statusBarContentColor: themeSystemBarContentColor(),
    navigationBarContentColor: themeSystemBarContentColor()
  }, 'set app transparent system bars');
}

export async function applyReaderWindowState(target: window.Window, keepScreenOn: boolean,
  orientation: window.Orientation | undefined, fullscreen: boolean = true): Promise<void> {
  rememberWindowPreferredOrientation(target);
  await setWindowKeepScreenOnQuietly(target, keepScreenOn, 'set reader keep screen on');
  if (orientation !== undefined) {
    await setPreferredOrientationQuietly(target, orientation, 'set reader orientation');
  }
  await setWindowLayoutFullScreenQuietly(target, true, 'set reader full-screen layout');
  await setWindowSystemBarEnableQuietly(target, fullscreen ? HIDDEN_SYSTEM_BARS : READER_STATUS_BAR_VISIBLE_SYSTEM_BARS,
    fullscreen ? 'hide reader system bar set' : 'show reader status bar');
  await setSpecificSystemBarEnabledQuietly(target, 'status', !fullscreen,
    fullscreen ? 'hide reader status bar' : 'show reader status bar');
  await setSpecificSystemBarEnabledQuietly(target, 'navigationIndicator', false, 'hide reader navigation indicator');
  await setWindowSystemBarPropertiesQuietly(target, {
    statusBarColor: themeTransparentColor(),
    navigationBarColor: themeTransparentColor(),
    isStatusBarLightIcon: fullscreen || isDarkTheme(),
    isNavigationBarLightIcon: true,
    statusBarContentColor: themeSystemBarContentColor()
  }, 'set reader transparent system bars');
}

export async function applyReaderWindowStateFromSettings(target: window.Window): Promise<void> {
  const keepScreenOn = ehSettingsStore.getValue('keep_screen_on', 'Off') === 'On';
  const fullscreen = ehSettingsStore.getValue('reading_fullscreen', 'On') === 'On';
  const orientationSetting = readerScreenRotationSetting();
  const orientation = orientationSetting === 'Match image' ? undefined : readerOrientationFromSetting(orientationSetting);
  await applyReaderWindowState(target, keepScreenOn, orientation, fullscreen);
}

export async function applyReaderBrightnessFromSettings(target: window.Window): Promise<void> {
  if (ehSettingsStore.getValue('ultra_dark_mode', 'Off') === 'On') {
    await setWindowBrightnessQuietly(target, 0, 'set reader ultra dark brightness');
    return;
  }
  if (ehSettingsStore.getValue('custom_screen_lightness', 'Off') !== 'On') {
    await setWindowBrightnessQuietly(target, -1, 'restore reader brightness');
    return;
  }
  const pct = Number.parseFloat(ehSettingsStore.getValue('screen_lightness', '50%')) / 100;
  const brightness = Number.isNaN(pct) ? 0.5 : Math.max(0, Math.min(1, pct));
  await setWindowBrightnessQuietly(target, brightness, 'set reader brightness');
}

export function rememberWindowPreferredOrientation(target: window.Window): void {
  try {
    const windowId = target.getWindowProperties().id;
    if (savedReaderPreferredOrientations.has(windowId)) {
      return;
    }
    pendingReaderExitOrientations.delete(windowId);
    savedReaderPreferredOrientations.set(windowId, target.getPreferredOrientation());
    const currentDisplayOrientation = readCurrentDisplayOrientation();
    if (currentDisplayOrientation !== undefined) {
      savedReaderDisplayOrientations.set(windowId, currentDisplayOrientation);
    }
    const currentWindowOrientation = readCurrentWindowOrientation(target);
    if (currentWindowOrientation !== undefined) {
      savedReaderWindowOrientations.set(windowId, currentWindowOrientation);
    }
  } catch (error) {
    logWindowError('remember reader previous orientation', error);
  }
}

export function readerScreenRotationSetting(): string {
  return normalizeReaderScreenRotationSetting(ehSettingsStore.getValue('screen_rotation', 'System'));
}

export function readerOrientationFromSetting(orientation: string): window.Orientation {
  const normalized = normalizeReaderScreenRotationSetting(orientation);
  if (normalized === 'Portrait') {
    return window.Orientation.AUTO_ROTATION_PORTRAIT;
  }
  if (normalized === 'Landscape') {
    return window.Orientation.AUTO_ROTATION_LANDSCAPE;
  }
  if (normalized === 'Auto rotate') {
    return window.Orientation.AUTO_ROTATION;
  }
  return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
}

export function readerOrientationFromImageMatch(target: window.Window, imageWidth: number,
  imageHeight: number): window.Orientation | undefined {
  if (imageWidth <= 0 || imageHeight <= 0 || imageWidth === imageHeight) {
    return undefined;
  }
  let screenWidth = 0;
  let screenHeight = 0;
  try {
    const rect = target.getWindowProperties().windowRect;
    screenWidth = rect.width;
    screenHeight = rect.height;
  } catch (error) {
    return undefined;
  }
  if (screenWidth <= 0 || screenHeight <= 0 || screenWidth === screenHeight) {
    return undefined;
  }
  return imageWidth > imageHeight ? window.Orientation.AUTO_ROTATION_LANDSCAPE :
  window.Orientation.AUTO_ROTATION_PORTRAIT;
}

export function normalizeReaderScreenRotationSetting(value: string): string {
  if (value === '1' || value === 'Portrait') {
    return 'Portrait';
  }
  if (value === '2' || value === 'Landscape') {
    return 'Landscape';
  }
  if (value === '3' || value === 'Sensor' || value === 'Auto rotate') {
    return 'Auto rotate';
  }
  if (value === '4' || value === 'Match image') {
    return 'Match image';
  }
  return 'Default';
}

export async function restoreAppWindowState(target: window.Window): Promise<void> {
  await setWindowKeepScreenOnQuietly(target, false, 'restore app keep screen on');
  await restoreWindowPreferredOrientation(target);
  await restoreAppWindowChrome(target);
}

async function restoreAppWindowChrome(target: window.Window): Promise<void> {
  const useLightSystemBarIcons = isDarkTheme();
  await setWindowSystemBarEnableQuietly(target, VISIBLE_SYSTEM_BARS, 'restore app system bar set');
  await setSpecificSystemBarEnabledQuietly(target, 'status', true, 'restore app status bar');
  await setSpecificSystemBarEnabledQuietly(target, 'navigationIndicator', false, 'restore app navigation indicator');
  await setWindowLayoutFullScreenQuietly(target, false, 'restore app non-full-screen layout');
  await setWindowSystemBarEnableQuietly(target, VISIBLE_SYSTEM_BARS, 'confirm app system bar set');
  await setSpecificSystemBarEnabledQuietly(target, 'status', true, 'confirm app status bar');
  await setSpecificSystemBarEnabledQuietly(target, 'navigationIndicator', false, 'confirm app navigation indicator');
  await setWindowSystemBarPropertiesQuietly(target, {
    statusBarColor: themeTransparentColor(),
    navigationBarColor: themeTransparentColor(),
    isStatusBarLightIcon: useLightSystemBarIcons,
    isNavigationBarLightIcon: useLightSystemBarIcons,
    statusBarContentColor: themeSystemBarContentColor(),
    navigationBarContentColor: themeSystemBarContentColor()
  }, 'restore app transparent system bars');
}

async function restoreWindowPreferredOrientation(target: window.Window): Promise<void> {
  let orientation = readerExitAutoRotationOrientation(target);
  let shouldConfirmOrientation = false;
  let forceOrientation = true;
  try {
    const windowId = target.getWindowProperties().id;
    const saved = savedReaderPreferredOrientations.get(windowId);
    const savedDisplayOrientation = savedReaderDisplayOrientations.get(windowId);
    const savedWindowOrientation = savedReaderWindowOrientations.get(windowId);
    const rotationLocked = isSystemRotationLocked();
    if (saved !== undefined) {
      orientation = saved;
      savedReaderPreferredOrientations.delete(windowId);
    }
    savedReaderDisplayOrientations.delete(windowId);
    savedReaderWindowOrientations.delete(windowId);
    if (rotationLocked) {
      const readerExitOrientation = savedWindowOrientation ?? orientationForDisplayOrientation(savedDisplayOrientation);
      if (readerExitOrientation !== undefined) {
        orientation = readerExitOrientation;
        pendingReaderExitOrientations.set(windowId, orientation);
        shouldConfirmOrientation = true;
        forceOrientation = false;
      }
    } else {
      orientation = readerExitAutoRotationOrientation(target);
      pendingReaderExitOrientations.delete(windowId);
      forceOrientation = true;
    }
  } catch (error) {
    logWindowError('read previous orientation', error);
  }
  await setPreferredOrientationQuietly(target, orientation, 'restore app orientation', forceOrientation);
  if (shouldConfirmOrientation) {
    schedulePendingReaderExitOrientation(target, 80);
    schedulePendingReaderExitOrientation(target, 260);
    schedulePendingReaderExitOrientation(target, 620);
    schedulePendingReaderExitOrientation(target, 1200);
  } else {
    scheduleReaderExitAutoRotationOrientation(target, 80);
    scheduleReaderExitAutoRotationOrientation(target, 260);
    scheduleReaderExitAutoRotationOrientation(target, 620);
    scheduleReaderExitAutoRotationOrientation(target, 1200);
  }
}

async function restorePendingReaderExitOrientation(target: window.Window): Promise<void> {
  try {
    const windowId = target.getWindowProperties().id;
    const orientation = pendingReaderExitOrientations.get(windowId);
    if (orientation === undefined) {
      return;
    }
    if (!shouldRestoreReaderExitOrientation(orientation)) {
      pendingReaderExitOrientations.delete(windowId);
      return;
    }
    await setPreferredOrientationQuietly(target, orientation, 'confirm reader exit orientation', true);
  } catch (error) {
    logWindowError('confirm reader exit orientation', error);
  }
}

function schedulePendingReaderExitOrientation(target: window.Window, delayMs: number): void {
  setTimeout(() => {
    restorePendingReaderExitOrientation(target).catch(() => {});
  }, delayMs);
}

function scheduleReaderExitAutoRotationOrientation(target: window.Window, delayMs: number): void {
  setTimeout(() => {
    if (isSystemRotationLocked()) {
      return;
    }
    setPreferredOrientationQuietly(target, readerExitAutoRotationOrientation(target),
      'confirm reader exit auto rotation', true).catch(() => {});
  }, delayMs);
}

function readCurrentDisplayOrientation(): display.Orientation | undefined {
  try {
    return display.getDefaultDisplaySync().orientation;
  } catch (error) {
    logWindowError('read current display orientation', error);
    return undefined;
  }
}

function readCurrentWindowOrientation(target: window.Window): window.Orientation | undefined {
  try {
    const rect = target.getWindowProperties().windowRect;
    if (rect.width > rect.height) {
      return window.Orientation.LANDSCAPE;
    }
    if (rect.height > rect.width) {
      return window.Orientation.PORTRAIT;
    }
    return undefined;
  } catch (error) {
    logWindowError('read current window orientation', error);
    return undefined;
  }
}

function readerExitAutoRotationOrientation(target: window.Window): window.Orientation {
  try {
    const rect = target.getWindowProperties().windowRect;
    return rect.width > rect.height ? window.Orientation.USER_ROTATION_LANDSCAPE :
    window.Orientation.USER_ROTATION_PORTRAIT;
  } catch (error) {
    logWindowError('read reader exit window orientation', error);
    return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
  }
}

function shouldRestoreReaderExitOrientation(_orientation: window.Orientation): boolean {
  return isSystemRotationLocked();
}

function isSystemRotationLocked(): boolean {
  try {
    const context = AppStorage.get<common.UIAbilityContext>('abilityContext') ??
    AppStorage.get<common.UIAbilityContext>('readerAbilityContext');
    if (context === undefined) {
      return false;
    }
    const status = settings.getValueSync(context, settings.general.ACCELEROMETER_ROTATION_STATUS, '1',
      settings.domainName.DEVICE_SHARED);
    return status === '0';
  } catch (error) {
    logWindowError('read system rotation lock', error);
    return false;
  }
}

function orientationForDisplayOrientation(orientation: display.Orientation | undefined): window.Orientation | undefined {
  if (orientation === display.Orientation.PORTRAIT) {
    return window.Orientation.PORTRAIT;
  }
  if (orientation === display.Orientation.LANDSCAPE) {
    return window.Orientation.LANDSCAPE;
  }
  if (orientation === display.Orientation.PORTRAIT_INVERTED) {
    return window.Orientation.PORTRAIT_INVERTED;
  }
  if (orientation === display.Orientation.LANDSCAPE_INVERTED) {
    return window.Orientation.LANDSCAPE_INVERTED;
  }
  return undefined;
}

async function setWindowKeepScreenOnQuietly(target: window.Window, keepScreenOn: boolean,
  operation: string): Promise<void> {
  try {
    await target.setWindowKeepScreenOn(keepScreenOn);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setWindowBrightnessQuietly(target: window.Window, brightness: number,
  operation: string): Promise<void> {
  try {
    await target.setWindowBrightness(brightness);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setPreferredOrientationQuietly(target: window.Window, orientation: window.Orientation,
  operation: string, force: boolean = false): Promise<void> {
  try {
    if (!force && target.getPreferredOrientation() === orientation) {
      return;
    }
    await target.setPreferredOrientation(orientation);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setWindowLayoutFullScreenQuietly(target: window.Window, enabled: boolean,
  operation: string): Promise<void> {
  try {
    await target.setWindowLayoutFullScreen(enabled);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setWindowSystemBarEnableQuietly(target: window.Window, names: SystemBarName[],
  operation: string): Promise<void> {
  try {
    await target.setWindowSystemBarEnable(names);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setSpecificSystemBarEnabledQuietly(target: window.Window, name: SpecificSystemBarName, enabled: boolean,
  operation: string): Promise<void> {
  try {
    await target.setSpecificSystemBarEnabled(name, enabled);
  } catch (error) {
    logWindowError(operation, error);
  }
}

async function setWindowSystemBarPropertiesQuietly(target: window.Window, properties: window.SystemBarProperties,
  operation: string): Promise<void> {
  try {
    await target.setWindowSystemBarProperties(properties);
  } catch (error) {
    logWindowError(operation, error);
  }
}

function logWindowError(operation: string, error: Error | Object | string): void {
  console.warn('EhWindowImmersive failed to ' + operation + ': ' + String(error));
}

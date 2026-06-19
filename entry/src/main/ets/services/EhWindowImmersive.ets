import { window } from '@kit.ArkUI';

export const MAIN_WINDOW_KEY: string = 'mainWindow';
export const READER_WINDOW_KEY: string = 'readerWindow';
export const EMBEDDED_READER_ACTIVE_KEY: string = 'embeddedReaderActive';
type SystemBarName = 'status' | 'navigation';

const VISIBLE_SYSTEM_BARS: SystemBarName[] = ['status', 'navigation'];
const HIDDEN_SYSTEM_BARS: SystemBarName[] = [];

export function rememberMainWindow(win: window.Window): void {
  AppStorage.set<window.Window | undefined>(MAIN_WINDOW_KEY, win);
}

export function getMainWindow(): window.Window | undefined {
  return AppStorage.get<window.Window>(MAIN_WINDOW_KEY);
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
  const target = win === undefined ? getMainWindow() : win;
  if (target === undefined) {
    return;
  }
  applyReaderWindowState(target, false, window.Orientation.UNSPECIFIED).catch(() => {});
}

export function enterEmbeddedReaderFullscreen(): void {
  setEmbeddedReaderActive(true);
  const target = getMainWindow();
  if (target === undefined) {
    return;
  }
  applyReaderWindowState(target, false, window.Orientation.UNSPECIFIED).catch(() => {});
  scheduleReaderFullscreenImmersiveMode(target, 32);
  scheduleReaderFullscreenImmersiveMode(target, 120);
  scheduleReaderFullscreenImmersiveMode(target, 320);
  scheduleReaderFullscreenImmersiveMode(target, 800);
}

export function leaveEmbeddedReaderFullscreen(): void {
  setEmbeddedReaderActive(false);
  const target = getMainWindow();
  if (target === undefined) {
    return;
  }
  restoreAppWindowState(target).then(() => {
    setTimeout(() => {
      applyAppChromeImmersiveMode(target);
    }, 32);
  }).catch(() => {});
}

export function scheduleReaderFullscreenImmersiveMode(win: window.Window, delayMs: number): void {
  setTimeout(() => {
    if (win === getMainWindow() && !isEmbeddedReaderActive()) {
      return;
    }
    applyReaderWindowState(win, false, window.Orientation.UNSPECIFIED).catch(() => {});
  }, delayMs);
}

async function applyAppChromeImmersiveModeAsync(target: window.Window): Promise<void> {
  await ignoreWindowError(() => target.setWindowLayoutFullScreen(true));
  await ignoreWindowError(() => target.setWindowSystemBarEnable(VISIBLE_SYSTEM_BARS));
  await ignoreWindowError(() => target.setWindowSystemBarProperties({
    statusBarColor: '#00000000',
    navigationBarColor: '#00000000',
    isStatusBarLightIcon: false,
    isNavigationBarLightIcon: false,
    statusBarContentColor: '#2B2027',
    navigationBarContentColor: '#2B2027'
  }));
}

export async function applyReaderWindowState(target: window.Window, keepScreenOn: boolean,
  orientation: window.Orientation): Promise<void> {
  await ignoreWindowError(() => target.setWindowKeepScreenOn(keepScreenOn), 'set reader keep screen on');
  await ignoreWindowError(() => target.setPreferredOrientation(orientation), 'set reader orientation');
  await ignoreWindowError(() => target.setWindowLayoutFullScreen(true), 'set reader full-screen layout');
  await ignoreWindowError(() => target.setWindowSystemBarEnable(HIDDEN_SYSTEM_BARS), 'hide reader system bar set');
  await ignoreWindowError(() => target.setWindowSystemBarProperties({
    statusBarColor: '#00000000',
    navigationBarColor: '#00000000',
    isStatusBarLightIcon: true,
    isNavigationBarLightIcon: true
  }), 'set reader transparent system bars');
}

export async function restoreAppWindowState(target: window.Window): Promise<void> {
  await ignoreWindowError(() => target.setWindowKeepScreenOn(false), 'restore app keep screen on');
  await ignoreWindowError(() => target.setPreferredOrientation(window.Orientation.UNSPECIFIED), 'restore app orientation');
  await ignoreWindowError(() => target.setWindowLayoutFullScreen(true), 'keep app full-screen layout');
  await ignoreWindowError(() => target.setWindowSystemBarEnable(VISIBLE_SYSTEM_BARS), 'restore app system bar set');
  await ignoreWindowError(() => target.setWindowSystemBarProperties({
    statusBarColor: '#00000000',
    navigationBarColor: '#00000000',
    isStatusBarLightIcon: false,
    isNavigationBarLightIcon: false,
    statusBarContentColor: '#2B2027',
    navigationBarContentColor: '#2B2027'
  }), 'restore app transparent system bars');
}

async function ignoreWindowError(task: () => Promise<void>, operation: string = 'update window chrome'): Promise<void> {
  try {
    await task();
  } catch (error) {
    console.warn('EhWindowImmersive failed to ' + operation + ': ' + String(error));
  }
}

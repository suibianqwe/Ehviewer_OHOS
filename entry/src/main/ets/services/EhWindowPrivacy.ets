import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { getMainWindow, getReaderWindow } from './EhWindowImmersive';

export const WINDOW_PRIVACY_STATUS_KEY: string = 'ehviewer_window_privacy_status';

export function applyWindowPrivacyMode(enabled: boolean, onStatus?: (status: string) => void,
  context?: common.UIAbilityContext): void {
  collectWindows(context).then((windows: window.Window[]) => {
    applyPrivacyModeToWindows(enabled, windows, onStatus);
  }).catch((error: Error) => {
    const fallbackWindows = currentWindows();
    if (fallbackWindows.length > 0) {
      applyPrivacyModeToWindows(enabled, fallbackWindows, onStatus);
      return;
    }
    const status = enabled ? 'Privacy mode failed: ' + error.message : 'Privacy mode disabled';
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
    if (onStatus !== undefined) {
      onStatus(status);
    }
  });
}

function applyPrivacyModeToWindows(enabled: boolean, windows: window.Window[], onStatus?: (status: string) => void): void {
  if (windows.length === 0) {
    const status = enabled ? 'Privacy mode pending: window is not ready' : 'Privacy mode disabled';
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
    if (onStatus !== undefined) {
      onStatus(status);
    }
    return;
  }

  Promise.all(windows.map((win: window.Window) => setWindowPrivacyModeResult(win, enabled))).then((results: WindowPrivacyResult[]) => {
    const failed = firstFailure(results);
    if (failed !== undefined) {
      const status = 'Privacy mode failed: ' + failed.message;
      AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
      if (onStatus !== undefined) {
        onStatus(status);
      }
      return;
    }
      const status = enabled ? 'Privacy mode enabled: screenshots and recording are blocked' : 'Privacy mode disabled';
      AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
      if (onStatus !== undefined) {
        onStatus(status);
      }
  }).catch((error: Error) => {
    const status = 'Privacy mode failed: ' + error.message;
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
    if (onStatus !== undefined) {
      onStatus(status);
    }
  });
}

async function collectWindows(context?: common.UIAbilityContext): Promise<window.Window[]> {
  const result = currentWindows();
  if (context !== undefined) {
    try {
      const lastWindow = await window.getLastWindow(context);
      addWindowIfMissing(result, lastWindow);
    } catch (error) {
      if (result.length === 0) {
        throw new Error(errorMessage(error));
      }
    }
  }
  return result;
}

function currentWindows(): window.Window[] {
  const result: window.Window[] = [];
  const mainWindow = getMainWindow();
  if (mainWindow !== undefined) {
    addWindowIfMissing(result, mainWindow);
  }
  const readerWindow = getReaderWindow();
  if (readerWindow !== undefined) {
    addWindowIfMissing(result, readerWindow);
  }
  return result;
}

function addWindowIfMissing(windows: window.Window[], target: window.Window): void {
  const targetId = windowId(target);
  for (let i = 0; i < windows.length; i++) {
    if (windows[i] === target || windowId(windows[i]) === targetId) {
      return;
    }
  }
  windows.push(target);
}

function setWindowPrivacyModeResult(win: window.Window, enabled: boolean): Promise<WindowPrivacyResult> {
  try {
    return win.setWindowPrivacyMode(enabled)
      .then(() => createWindowPrivacyResult(true, ''))
      .catch((error: BusinessError) => createWindowPrivacyResult(false, privacyErrorMessage(error)));
  } catch (error) {
    return Promise.resolve(createWindowPrivacyResult(false, privacyErrorMessage(error)));
  }
}

function createWindowPrivacyResult(ok: boolean, message: string): WindowPrivacyResult {
  const result: WindowPrivacyResult = {
    ok: ok,
    message: message
  };
  return result;
}

function firstFailure(results: WindowPrivacyResult[]): WindowPrivacyResult | undefined {
  for (let i = 0; i < results.length; i++) {
    if (!results[i].ok) {
      return results[i];
    }
  }
  return undefined;
}

function privacyErrorMessage(error: Error | Object | string): string {
  const message = errorMessage(error);
  const code = errorCode(error);
  if (code === 201) {
    return 'missing ohos.permission.PRIVACY_WINDOW permission';
  }
  if (code === 1300002) {
    return 'window is not ready or has been destroyed';
  }
  if (code > 0) {
    return 'code ' + code.toString() + ': ' + message;
  }
  return message.length > 0 ? message : 'unknown error';
}

function errorMessage(error: Error | Object | string): string {
  if (error instanceof Error) {
    return error.message;
  }
  if (typeof error === 'string') {
    return error;
  }
  const candidate = error as Record<string, Object>;
  if (typeof candidate.message === 'string') {
    return candidate.message;
  }
  return JSON.stringify(error);
}

function errorCode(error: Error | Object | string): number {
  if (typeof error !== 'object' || error === null) {
    return 0;
  }
  const candidate = error as Record<string, Object>;
  if (typeof candidate.code === 'number') {
    return candidate.code;
  }
  return 0;
}

function windowId(win: window.Window): number {
  try {
    return win.getWindowProperties().id;
  } catch (error) {
    return -1;
  }
}

interface WindowPrivacyResult {
  ok: boolean;
  message: string;
}

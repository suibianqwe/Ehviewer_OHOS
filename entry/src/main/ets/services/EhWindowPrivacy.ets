import { window } from '@kit.ArkUI';

const MAIN_WINDOW_KEY: string = 'mainWindow';
export const WINDOW_PRIVACY_STATUS_KEY: string = 'ehviewer_window_privacy_status';

export function applyWindowPrivacyMode(enabled: boolean, onStatus?: (status: string) => void): void {
  const win = AppStorage.get<window.Window>(MAIN_WINDOW_KEY);
  if (win === undefined) {
    const status = enabled ? 'Secure screen pending: main window is not ready' : 'Secure screen disabled';
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
    if (onStatus !== undefined) {
      onStatus(status);
    }
    return;
  }

  try {
    win.setWindowPrivacyMode(enabled).then(() => {
      const status = enabled ? 'Secure screen enabled: screenshots and recording are blocked' : 'Secure screen disabled';
      AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
      if (onStatus !== undefined) {
        onStatus(status);
      }
    }).catch((error: Error) => {
      const status = 'Secure screen failed: ' + error.message;
      AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
      if (onStatus !== undefined) {
        onStatus(status);
      }
    });
  } catch (error) {
    const status = 'Secure screen failed: ' + String(error);
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, status);
    if (onStatus !== undefined) {
      onStatus(status);
    }
  }
}

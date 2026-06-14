import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { userAuth } from '@kit.UserAuthenticationKit';
import { applyWindowPrivacyMode, WINDOW_PRIVACY_STATUS_KEY } from '../services/EhWindowPrivacy';

const SETTINGS_PREF_NAME: string = 'ehviewer_settings';
const SETTINGS_VALUES_KEY: string = 'values';
const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';
const MAIN_WINDOW_KEY: string = 'mainWindow';
const LANGUAGE_REVISION_KEY: string = 'ehviewer_language_revision';

interface SettingEntry {
  key: string;
  value: string;
}

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | undefined = undefined;
  private authPending: boolean = false;
  private mainWindow: window.Window | undefined = undefined;

  onWindowStageCreate(stage: window.WindowStage): void {
    this.windowStage = stage;
    AppStorage.setOrCreate('abilityContext', this.context);
    AppStorage.setOrCreate<number>(STATUS_BAR_HEIGHT_KEY, 0);
    AppStorage.setOrCreate<window.Window | undefined>(MAIN_WINDOW_KEY, undefined);
    AppStorage.setOrCreate<number>(LANGUAGE_REVISION_KEY, 0);
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, '');
    stage.loadContent('pages/Index', (error) => {
      if (error.code) {
        console.error(`Failed to load the main page. code=${error.code}, message=${error.message}`);
      }
    });
    stage.getMainWindow().then((win) => {
      this.mainWindow = win;
      AppStorage.set<window.Window | undefined>(MAIN_WINDOW_KEY, win);
      win.setWindowLayoutFullScreen(true);
      win.setWindowSystemBarEnable(['status']);
      win.setWindowSystemBarProperties({
        statusBarColor: '#FF2F6F8F',
        isStatusBarLightIcon: true
      });
      this.updateSystemAvoidArea(win);
      win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.set<number>(STATUS_BAR_HEIGHT_KEY, data.area.topRect.height);
        }
      });
      this.applyPersistedSecureScreen();
    }).catch(() => {});
  }

  private updateSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.set<number>(STATUS_BAR_HEIGHT_KEY, area.topRect.height);
    } catch (error) {
      AppStorage.set<number>(STATUS_BAR_HEIGHT_KEY, 0);
    }
  }

  onForeground(): void {
    this.applyPersistedSecureScreen();
    if (this.authPending) {
      return;
    }
    this.checkAndPromptBiometricLock();
  }

  private applyPersistedSecureScreen(): void {
    preferences.getPreferences(this.context, { name: SETTINGS_PREF_NAME }).then((prefs) => {
      return prefs.get(SETTINGS_VALUES_KEY, '');
    }).then((raw) => {
      let enabled = false;
      if (typeof raw === 'string' && raw.length > 0) {
        try {
          const entries = JSON.parse(raw) as SettingEntry[];
          if (Array.isArray(entries)) {
            for (let i = 0; i < entries.length; i++) {
              if (entries[i].key === 'enable_secure') {
                enabled = entries[i].value === 'On';
                break;
              }
            }
          }
        } catch (error) {
          enabled = false;
        }
      }
      applyWindowPrivacyMode(enabled);
    }).catch(() => {
      applyWindowPrivacyMode(false);
    });
  }

  private checkAndPromptBiometricLock(): void {
    preferences.getPreferences(this.context, { name: SETTINGS_PREF_NAME }).then((prefs) => {
      return prefs.get(SETTINGS_VALUES_KEY, '');
    }).then((raw) => {
      if (typeof raw !== 'string' || raw.length === 0) {
        return;
      }
      let enabled = false;
      try {
        const entries = JSON.parse(raw) as SettingEntry[];
        if (Array.isArray(entries)) {
          for (let i = 0; i < entries.length; i++) {
            if (entries[i].key === 'pattern_protection' && entries[i].value === 'On') {
              enabled = true;
              break;
            }
          }
        }
      } catch (error) {
        return;
      }
      if (!enabled) {
        return;
      }
      this.promptBiometricAuth();
    }).catch(() => {});
  }

  private promptBiometricAuth(): void {
    try {
      const challenge = generateChallenge();
      const authParam: userAuth.AuthParam = {
        challenge: challenge,
        authType: [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE, userAuth.UserAuthType.PIN],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = {
        title: 'EhViewer — Verify identity'
      };
      const authInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      this.authPending = true;
      authInstance.on('result', {
        onResult: (result: userAuth.UserAuthResult) => {
          this.authPending = false;
          if (result.result !== userAuth.UserAuthResultCode.SUCCESS) {
            this.minimizeApp();
          }
        }
      });
      authInstance.start();
    } catch (error) {
      this.authPending = false;
    }
  }

  private minimizeApp(): void {
    if (this.windowStage === undefined) {
      return;
    }
    try {
      this.windowStage.getMainWindow().then((win) => {
        win.minimize();
      }).catch(() => {});
    } catch (error) {
    }
  }
}

function generateChallenge(): Uint8Array {
  const bytes = new Uint8Array(32);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Math.floor(Math.random() * 256);
  }
  return bytes;
}

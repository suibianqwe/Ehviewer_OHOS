import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { userAuth } from '@kit.UserAuthenticationKit';
import { MAIN_WINDOW_KEY, prepareAppChromeBeforeContent, rememberMainWindow } from '../services/EhWindowImmersive';
import { applyWindowPrivacyMode, WINDOW_PRIVACY_STATUS_KEY } from '../services/EhWindowPrivacy';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehAppLog } from '../services/EhAppLog';
import { startEhFrontingBenchmark } from '../services/EhNetworkConfig';

const SETTINGS_PREF_NAME: string = 'ehviewer_settings';
const SETTINGS_VALUES_KEY: string = 'values';
const STATUS_BAR_HEIGHT_KEY: string = 'statusBarHeight';
const TOP_AVOID_HEIGHT_KEY: string = 'topAvoidHeight';
const BOTTOM_AVOID_HEIGHT_KEY: string = 'bottomAvoidHeight';
const LANGUAGE_REVISION_KEY: string = 'ehviewer_language_revision';

interface SettingEntry {
  key: string;
  value: string;
}

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | undefined = undefined;
  private authPending: boolean = false;
  // Largest bottom avoid (nav bar / gesture indicator) height observed this session, in px.
  // The reader hides system bars (setWindowSystemBarEnable([])), which makes the live avoid
  // area report 0 — but the gesture indicator zone physically persists. We keep the max-seen
  // value so the reader can still inset its bottom bar clear of that zone.
  private maxBottomAvoidPx: number = 0;

  onWindowStageCreate(stage: window.WindowStage): void {
    this.windowStage = stage;
    AppStorage.setOrCreate('abilityContext', this.context);
    AppStorage.setOrCreate<number>(STATUS_BAR_HEIGHT_KEY, 0);
    AppStorage.setOrCreate<number>(TOP_AVOID_HEIGHT_KEY, 0);
    AppStorage.setOrCreate<number>(BOTTOM_AVOID_HEIGHT_KEY, 0);
    AppStorage.setOrCreate<window.Window | undefined>(MAIN_WINDOW_KEY, undefined);
    AppStorage.setOrCreate<number>(LANGUAGE_REVISION_KEY, 0);
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, '');
    const windowReady = stage.getMainWindow().then((win) => {
      rememberMainWindow(win);
      this.updateWindowAvoidAreas(win);
      return prepareAppChromeBeforeContent(win).then(() => {
        this.updateWindowAvoidAreas(win);
        win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
          this.updateChangedAvoidArea(win, data);
        });
        this.applyPersistedSecureScreen();
      });
    }).catch(() => {});
    const settingsReady = ehSettingsStore.load(this.context).then(() => {
      startEhFrontingBenchmark(this.context);
    }).catch(() => {});
    Promise.all([windowReady, settingsReady]).then(() => {
      this.loadIndexContent(stage);
    }).catch(() => {
      this.loadIndexContent(stage);
    });
  }

  private loadIndexContent(stage: window.WindowStage): void {
    stage.loadContent('pages/Index', (error) => {
      if (error.code) {
        console.error(`Failed to load the main page. code=${error.code}, message=${error.message}`);
        ehAppLog.error(this.context, 'EntryAbility', 'Failed to load main page: ' + error.message);
      }
    });
  }

  private updateWindowAvoidAreas(win: window.Window): void {
    this.updateSystemAvoidArea(win);
    this.updateBottomAvoidArea(win);
  }

  private updateChangedAvoidArea(win: window.Window, data: window.AvoidAreaOptions): void {
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      this.setTopAvoidArea(win, data.area);
    }
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM ||
        data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.updateBottomAvoidArea(win);
    }
  }

  private updateSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.setTopAvoidArea(win, area);
    } catch (error) {
      AppStorage.set<number>(STATUS_BAR_HEIGHT_KEY, 0);
      AppStorage.set<number>(TOP_AVOID_HEIGHT_KEY, 0);
    }
  }

  // Bottom avoid = max(TYPE_SYSTEM.bottom, TYPE_NAVIGATION_INDICATOR.bottom), kept as a
  // session sticky-max so it survives the reader hiding the system bars (which reports 0).
  private updateBottomAvoidArea(win: window.Window): void {
    let bottomPx = 0;
    try {
      bottomPx = Math.max(bottomPx,
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height);
    } catch (error) {}
    try {
      bottomPx = Math.max(bottomPx,
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
    } catch (error) {}
    if (bottomPx > this.maxBottomAvoidPx) {
      this.maxBottomAvoidPx = bottomPx;
    }
    try {
      AppStorage.set<number>(BOTTOM_AVOID_HEIGHT_KEY, win.getUIContext().px2vp(this.maxBottomAvoidPx));
    } catch (error) {
      AppStorage.set<number>(BOTTOM_AVOID_HEIGHT_KEY, 0);
    }
  }

  private setTopAvoidArea(win: window.Window, area: window.AvoidArea): void {
    AppStorage.set<number>(STATUS_BAR_HEIGHT_KEY, area.topRect.height);
    try {
      AppStorage.set<number>(TOP_AVOID_HEIGHT_KEY, win.getUIContext().px2vp(area.topRect.height));
    } catch (error) {
      AppStorage.set<number>(TOP_AVOID_HEIGHT_KEY, 0);
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
      return prefs.get(SETTINGS_VALUES_KEY, '').catch(() => '');
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
      return prefs.get(SETTINGS_VALUES_KEY, '').catch(() => '');
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
        try {
          win.minimize().catch(() => {});
        } catch (error) {
        }
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

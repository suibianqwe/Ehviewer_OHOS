import { Configuration, ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { userAuth } from '@kit.UserAuthenticationKit';
import {
  EMBEDDED_READER_ACTIVE_KEY,
  MAIN_WINDOW_KEY,
  prepareAppChromeBeforeContent,
  rememberMainWindow
} from '../services/EhWindowImmersive';
import { applyWindowPrivacyMode, WINDOW_PRIVACY_STATUS_KEY } from '../services/EhWindowPrivacy';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { ehAppLog } from '../services/EhAppLog';
import { EH_SYSTEM_COLOR_MODE_DARK, EH_SYSTEM_COLOR_MODE_KEY } from '../shared/EhTheme';
import {
  isEhDirectConnectionProbeEnabled,
  startEhDirectConnectionProbe,
  startEhFrontingBenchmark
} from '../services/EhNetworkConfig';
import {
  resetCellularNetworkWarningConfirmation,
  shouldWarnForCellularNetwork
} from '../services/EhCellularNetworkGuard';
import {
  IDENTITY_AUTH_FACE_FIRST,
  IDENTITY_AUTH_FINGERPRINT_FIRST,
  IDENTITY_AUTH_LOCKED_KEY,
  IDENTITY_AUTH_OFF,
  IDENTITY_AUTH_PASSWORD_FIRST,
  THEME_REVISION_KEY,
  notifyThemeChanged,
  normalizeIdentityAuthenticationOption,
  uiText
} from '../shared/EhShared';

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
  private identityAuthGraceUntilMs: number = 0;
  private startupDirectProbeToast: string = '';
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
    AppStorage.setOrCreate<number>(THEME_REVISION_KEY, 0);
    AppStorage.setOrCreate<string>(WINDOW_PRIVACY_STATUS_KEY, '');
    AppStorage.setOrCreate<boolean>(IDENTITY_AUTH_LOCKED_KEY, false);
    AppStorage.setOrCreate<boolean>(EMBEDDED_READER_ACTIVE_KEY, false);
    this.updateSystemColorMode(this.context.config.colorMode);
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
      this.setIdentityAuthLocked(this.identityAuthEnabledInMemory());
      if (!isEhDirectConnectionProbeEnabled()) {
        return;
      }
      return startEhDirectConnectionProbe(this.context).then((directAvailable: boolean) => {
        this.startupDirectProbeToast = directAvailable
          ? 'Direct connection available, domain fronting disabled'
          : 'Direct connection unavailable, domain fronting enabled';
        if (!directAvailable) {
          startEhFrontingBenchmark(this.context);
        }
      });
    }).catch(() => {});
    Promise.all([windowReady, settingsReady]).then(() => {
      this.loadIndexContent(stage);
    }).catch(() => {
      this.loadIndexContent(stage);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.updateSystemColorMode(newConfig.colorMode);
  }

  private updateSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    const normalized = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? EH_SYSTEM_COLOR_MODE_DARK : 0;
    const previous = AppStorage.get<number>(EH_SYSTEM_COLOR_MODE_KEY);
    AppStorage.setOrCreate<number>(EH_SYSTEM_COLOR_MODE_KEY, normalized);
    if (previous !== undefined && previous !== normalized) {
      notifyThemeChanged();
    }
  }

  private loadIndexContent(stage: window.WindowStage): void {
    stage.loadContent('pages/Index', (error) => {
      if (error.code) {
        console.error(`Failed to load the main page. code=${error.code}, message=${error.message}`);
        ehAppLog.error(this.context, 'EntryAbility', 'Failed to load main page: ' + error.message);
        return;
      }
      resetCellularNetworkWarningConfirmation();
      this.checkAndPromptBiometricLock();
      this.showStartupCellularNetworkWarning();
      this.showStartupDirectProbeToast();
    });
  }

  private showStartupCellularNetworkWarning(): void {
    if (!shouldWarnForCellularNetwork() || this.windowStage === undefined) {
      return;
    }
    try {
      this.windowStage.getMainWindow().then((win) => {
        try {
          win.getUIContext().getPromptAction().showToast({ message: uiText('Connected to cellular networks') });
        } catch (error) {
        }
      }).catch(() => {});
    } catch (error) {
    }
  }

  private showStartupDirectProbeToast(): void {
    if (this.startupDirectProbeToast.length === 0 || this.windowStage === undefined) {
      return;
    }
    const message = this.startupDirectProbeToast;
    this.startupDirectProbeToast = '';
    try {
      this.windowStage.getMainWindow().then((win) => {
        try {
          win.getUIContext().getPromptAction().showToast({ message: uiText(message) });
        } catch (error) {
        }
      }).catch(() => {});
    } catch (error) {
    }
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
    if (Date.now() < this.identityAuthGraceUntilMs) {
      return;
    }
    if (this.identityAuthEnabledInMemory()) {
      this.setIdentityAuthLocked(true);
    }
    this.checkAndPromptBiometricLock();
  }

  onBackground(): void {
    if (this.authPending) {
      return;
    }
    if (this.identityAuthEnabledInMemory()) {
      this.setIdentityAuthLocked(true);
    }
    this.applyPersistedSecureScreen();
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
      applyWindowPrivacyMode(enabled, undefined, this.context);
    }).catch(() => {
      applyWindowPrivacyMode(false, undefined, this.context);
    });
  }

  private checkAndPromptBiometricLock(): void {
    preferences.getPreferences(this.context, { name: SETTINGS_PREF_NAME }).then((prefs) => {
      return prefs.get(SETTINGS_VALUES_KEY, '').catch(() => '');
    }).then((raw) => {
      if (typeof raw !== 'string' || raw.length === 0) {
        return;
      }
      let mode = IDENTITY_AUTH_OFF;
      try {
        const entries = JSON.parse(raw) as SettingEntry[];
        if (Array.isArray(entries)) {
          for (let i = 0; i < entries.length; i++) {
            if (entries[i].key === 'pattern_protection') {
              mode = normalizeIdentityAuthenticationOption(entries[i].value);
              break;
            }
          }
        }
      } catch (error) {
        return;
      }
      if (mode === IDENTITY_AUTH_OFF) {
        this.setIdentityAuthLocked(false);
        return;
      }
      this.setIdentityAuthLocked(true);
      this.promptBiometricAuth(mode);
    }).catch(() => {});
  }

  private promptBiometricAuth(mode: string): void {
    if (this.authPending) {
      return;
    }
    this.authPending = true;
    this.startNextIdentityAuth(this.identityAuthTypeSequenceForMode(mode), 0);
  }

  private startNextIdentityAuth(types: userAuth.UserAuthType[], index: number): void {
    if (index >= types.length) {
      this.authPending = false;
      this.setIdentityAuthLocked(true);
      this.minimizeApp();
      return;
    }
    const authType = types[index];
    if (!this.identityAuthTypeAvailable(authType)) {
      this.startNextIdentityAuth(types, index + 1);
      return;
    }
    try {
      const challenge = generateChallenge();
      const authParam: userAuth.AuthParam = {
        challenge: challenge,
        authType: [authType],
        authTrustLevel: this.identityAuthTrustLevel(authType),
        skipLockedBiometricAuth: true
      };
      const widgetParam: userAuth.WidgetParam = {
        title: this.identityAuthTitle(authType),
        navigationButtonText: uiText('Cancel')
      };
      const authInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      authInstance.on('result', {
        onResult: (result: userAuth.UserAuthResult) => {
          this.authPending = false;
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            this.identityAuthGraceUntilMs = Date.now() + 5000;
            this.setIdentityAuthLocked(false);
          } else if (this.shouldTryNextIdentityAuthType(result.result)) {
            this.authPending = true;
            this.startNextIdentityAuth(types, index + 1);
          } else {
            this.setIdentityAuthLocked(true);
            this.minimizeApp();
          }
        }
      });
      authInstance.start();
    } catch (error) {
      if (this.shouldTryNextIdentityAuthType(this.errorCode(error))) {
        this.startNextIdentityAuth(types, index + 1);
        return;
      }
      this.authPending = false;
      this.setIdentityAuthLocked(true);
      this.minimizeApp();
    }
  }

  private identityAuthEnabledInMemory(): boolean {
    return normalizeIdentityAuthenticationOption(ehSettingsStore.getValue('pattern_protection', 'Off')) !== IDENTITY_AUTH_OFF;
  }

  private setIdentityAuthLocked(locked: boolean): void {
    AppStorage.setOrCreate<boolean>(IDENTITY_AUTH_LOCKED_KEY, locked);
  }

  private identityAuthTypeSequenceForMode(mode: string): userAuth.UserAuthType[] {
    const normalizedMode = normalizeIdentityAuthenticationOption(mode);
    if (normalizedMode === IDENTITY_AUTH_FACE_FIRST) {
      return [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.PIN];
    }
    if (normalizedMode === IDENTITY_AUTH_PASSWORD_FIRST) {
      return [userAuth.UserAuthType.PIN, userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE];
    }
    if (normalizedMode === IDENTITY_AUTH_FINGERPRINT_FIRST) {
      return [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE, userAuth.UserAuthType.PIN];
    }
    return [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE, userAuth.UserAuthType.PIN];
  }

  private identityAuthTypeAvailable(authType: userAuth.UserAuthType): boolean {
    try {
      userAuth.getAvailableStatus(authType, this.identityAuthTrustLevel(authType));
      return true;
    } catch (error) {
      return false;
    }
  }

  private identityAuthTrustLevel(authType: userAuth.UserAuthType): userAuth.AuthTrustLevel {
    return authType === userAuth.UserAuthType.PIN ? userAuth.AuthTrustLevel.ATL3 : userAuth.AuthTrustLevel.ATL1;
  }

  private identityAuthTitle(authType: userAuth.UserAuthType): string {
    if (authType === userAuth.UserAuthType.PIN) {
      return 'EhViewer ' + uiText('Password first');
    }
    if (authType === userAuth.UserAuthType.FACE) {
      return 'EhViewer ' + uiText('Face first');
    }
    return 'EhViewer ' + uiText('Fingerprint first');
  }

  private shouldTryNextIdentityAuthType(resultCode: number): boolean {
    return resultCode === userAuth.UserAuthResultCode.TYPE_NOT_SUPPORT ||
      resultCode === userAuth.UserAuthResultCode.TRUST_LEVEL_NOT_SUPPORT ||
      resultCode === userAuth.UserAuthResultCode.NOT_ENROLLED ||
      resultCode === userAuth.UserAuthResultCode.LOCKED ||
      resultCode === userAuth.UserAuthResultCode.BUSY;
  }

  private errorCode(error: Error | Object | string): number {
    if (typeof error !== 'object' || error === null) {
      return 0;
    }
    const candidate = error as Record<string, Object>;
    if (typeof candidate.code === 'number') {
      return candidate.code;
    }
    return 0;
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

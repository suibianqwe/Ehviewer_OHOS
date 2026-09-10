import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  applyReaderBrightnessFromSettings,
  applyReaderFullscreenImmersiveMode,
  clearReaderWindow,
  rememberReaderWindow,
  restoreAppWindowState
} from '../services/EhWindowImmersive';
import { ehAppLog } from '../services/EhAppLog';
import { ehSettingsStore } from '../services/EhSettingsStore';
import { refreshEhConnectionsAfterForeground } from '../services/EhNetworkConfig';
import { cancelQueuedReaderImageRequests } from '../services/ReaderImageCache';
import { applyWindowPrivacyMode } from '../services/EhWindowPrivacy';
import { EH_SYSTEM_COLOR_MODE_DARK, EH_SYSTEM_COLOR_MODE_KEY } from '../shared/EhTheme';
import { notifyLanguageChanged, notifyThemeChanged } from '../shared/EhShared';
import {
  buildReaderContinuationSnapshot,
  putContinuationSnapshot,
  readContinuationSnapshot,
  applyMissionContinuationSetting,
  isMultiDeviceContinuationEnabled
} from '../services/DistributedContinuationService';
import { readerSessionStore } from '../services/ReaderSessionStore';

export const READER_ABILITY_CONTEXT_KEY: string = 'readerAbilityContext';

export default class ReaderAbility extends UIAbility {
  private readerWindow: window.Window | undefined = undefined;
  private appWasBackground: boolean = false;
  private windowStateRestoreStarted: boolean = false;

  onCreate(want: Want): void {
    this.restoreContinuationSession(want);
  }

  onNewWant(want: Want): void {
    this.restoreContinuationSession(want);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (!isMultiDeviceContinuationEnabled()) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    const session = readerSessionStore.getSession();
    if (session === null || session.pageIndex < 0) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    const snapshot = buildReaderContinuationSnapshot('standalone_reader', 'reader', session);
    return putContinuationSnapshot(wantParam, snapshot) ?
      AbilityConstant.OnContinueResult.AGREE : AbilityConstant.OnContinueResult.REJECT;
  }

  onWindowStageRestore(stage: window.WindowStage): void {
    this.onWindowStageCreate(stage);
  }

  private restoreContinuationSession(want: Want): void {
    const snapshot = readContinuationSnapshot(want);
    if (snapshot === null || snapshot.kind !== 'standalone_reader' || snapshot.readerSession === undefined) {
      return;
    }
    readerSessionStore.setSession(snapshot.readerSession);
  }

  private enableMissionContinuation(): void {
    applyMissionContinuationSetting(this.context);
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    this.enableMissionContinuation();
    AppStorage.setOrCreate(READER_ABILITY_CONTEXT_KEY, this.context);
    this.updateSystemColorMode(this.context.config.colorMode);
    try {
      const win = stage.getMainWindowSync();
      this.readerWindow = win;
      rememberReaderWindow(win);
      this.applyReaderChrome(win);
      this.loadSettingsAndApplyReaderChrome(win);
    } catch (error) {
    }
    stage.loadContent('pages/Reader', (error) => {
      if (error.code) {
        console.error(`Failed to load reader page. code=${error.code}, message=${error.message}`);
        ehAppLog.error(this.context, 'ReaderAbility', 'Failed to load reader page: ' + error.message);
        return;
      }
      const win = this.ensureReaderWindow(stage);
      if (win !== undefined) {
        this.applyReaderChrome(win);
        this.loadSettingsAndApplyReaderChrome(win);
        this.scheduleReaderChrome(win, 32);
        this.scheduleReaderChrome(win, 160);
        this.scheduleReaderChrome(win, 480);
      }
    });
  }

  onForeground(): void {
    if (this.appWasBackground) {
      this.appWasBackground = false;
      refreshEhConnectionsAfterForeground();
    }
    if (this.readerWindow !== undefined) {
      this.applyReaderChrome(this.readerWindow);
      this.loadSettingsAndApplyReaderChrome(this.readerWindow);
      this.scheduleReaderChrome(this.readerWindow, 120);
    }
  }

  private applyReaderChrome(win: window.Window): void {
    applyReaderFullscreenImmersiveMode(win);
    applyReaderBrightnessFromSettings(win).catch(() => {});
  }

  private loadSettingsAndApplyReaderChrome(win: window.Window): void {
    ehSettingsStore.ensureLoaded(this.context).finally(() => {
      applyMissionContinuationSetting(this.context);
      this.applyReaderChrome(win);
      applyWindowPrivacyMode(ehSettingsStore.getValue('enable_secure', 'Off') === 'On', undefined, this.context);
      this.scheduleReaderChrome(win, 80);
      this.scheduleReaderChrome(win, 260);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    notifyLanguageChanged();
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

  onBackground(): void {
    this.appWasBackground = true;
  }

  private ensureReaderWindow(stage: window.WindowStage): window.Window | undefined {
    if (this.readerWindow !== undefined) {
      return this.readerWindow;
    }
    try {
      const win = stage.getMainWindowSync();
      this.readerWindow = win;
      rememberReaderWindow(win);
      return win;
    } catch (error) {
      return undefined;
    }
  }

  private scheduleReaderChrome(win: window.Window, delayMs: number): void {
    setTimeout(() => {
      if (this.readerWindow === win) {
        this.applyReaderChrome(win);
      }
    }, delayMs);
  }

  onWindowStageDestroy(): void {
    cancelQueuedReaderImageRequests();
    this.restoreReaderWindowStateOnce();
    clearReaderWindow();
    this.readerWindow = undefined;
  }

  onDestroy(): void {
    cancelQueuedReaderImageRequests();
    this.restoreReaderWindowStateOnce();
    clearReaderWindow();
    AppStorage.set<common.UIAbilityContext | undefined>(READER_ABILITY_CONTEXT_KEY, undefined);
  }

  private restoreReaderWindowStateOnce(): void {
    if (this.windowStateRestoreStarted || this.readerWindow === undefined) {
      return;
    }
    this.windowStateRestoreStarted = true;
    restoreAppWindowState(this.readerWindow).catch(() => {});
  }

}

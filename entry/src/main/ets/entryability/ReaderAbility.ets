import { UIAbility, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  applyReaderFullscreenImmersiveMode,
  clearReaderWindow,
  rememberReaderWindow,
  restoreAppWindowState
} from '../services/EhWindowImmersive';

export const READER_ABILITY_CONTEXT_KEY: string = 'readerAbilityContext';

export default class ReaderAbility extends UIAbility {
  private readerWindow: window.Window | undefined = undefined;

  onWindowStageCreate(stage: window.WindowStage): void {
    AppStorage.setOrCreate(READER_ABILITY_CONTEXT_KEY, this.context);
    try {
      const win = stage.getMainWindowSync();
      this.readerWindow = win;
      rememberReaderWindow(win);
      this.applyReaderChrome(win);
    } catch (error) {
    }
    stage.loadContent('pages/Reader', (error) => {
      if (error.code) {
        console.error(`Failed to load reader page. code=${error.code}, message=${error.message}`);
        return;
      }
      const win = this.ensureReaderWindow(stage);
      if (win !== undefined) {
        this.applyReaderChrome(win);
        this.scheduleReaderChrome(win, 32);
        this.scheduleReaderChrome(win, 160);
        this.scheduleReaderChrome(win, 480);
      }
    });
  }

  onForeground(): void {
    if (this.readerWindow !== undefined) {
      this.applyReaderChrome(this.readerWindow);
      this.scheduleReaderChrome(this.readerWindow, 120);
    }
  }

  private applyReaderChrome(win: window.Window): void {
    applyReaderFullscreenImmersiveMode(win);
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
    if (this.readerWindow !== undefined) {
      restoreAppWindowState(this.readerWindow).catch(() => {});
    }
    clearReaderWindow();
    this.readerWindow = undefined;
  }

  onDestroy(): void {
    if (this.readerWindow !== undefined) {
      restoreAppWindowState(this.readerWindow).catch(() => {});
    }
    clearReaderWindow();
    AppStorage.set<common.UIAbilityContext | undefined>(READER_ABILITY_CONTEXT_KEY, undefined);
  }
}

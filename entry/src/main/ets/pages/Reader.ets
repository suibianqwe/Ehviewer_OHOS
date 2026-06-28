import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ReaderHostScene } from '../components/ReaderHostScene';
import {
  applyReaderBrightnessFromSettings,
  applyReaderFullscreenImmersiveMode,
  getReaderWindow,
  rememberReaderWindow,
  applyReaderWindowStateFromSettings,
  scheduleReaderFullscreenImmersiveMode
} from '../services/EhWindowImmersive';
import { THEME_REVISION_KEY, runReaderActiveBackHandler } from '../shared/EhShared';

@Entry
@Component
struct ReaderPage {
  @StorageProp(THEME_REVISION_KEY) themeRevision: number = 0;

  aboutToAppear(): void {
    this.applyReaderEntryChrome();
  }

  onPageShow(): void {
    this.applyReaderEntryChrome();
  }

  onBackPress(): boolean {
    if (runReaderActiveBackHandler()) {
      return true;
    }
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (hostContext !== undefined) {
      hostContext.terminateSelf().catch(() => {});
    }
    return true;
  }

  private applyReaderEntryChrome(): void {
    this.applyReaderEntryChromeAsync().catch(() => {});
  }

  private async applyReaderEntryChromeAsync(): Promise<void> {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (hostContext !== undefined) {
        const win = hostContext.windowStage.getMainWindowSync();
        rememberReaderWindow(win);
        await this.applyReaderWindowChrome(win);
        return;
      }
    } catch (error) {
    }
    const win = getReaderWindow();
    if (win === undefined) {
      applyReaderFullscreenImmersiveMode();
      return;
    }
    await this.applyReaderWindowChrome(win);
  }

  private async applyReaderWindowChrome(win: window.Window): Promise<void> {
    await applyReaderWindowStateFromSettings(win);
    await applyReaderBrightnessFromSettings(win);
    scheduleReaderFullscreenImmersiveMode(win, 16);
    this.scheduleReaderBrightness(win, 16);
    scheduleReaderFullscreenImmersiveMode(win, 80);
    this.scheduleReaderBrightness(win, 80);
    scheduleReaderFullscreenImmersiveMode(win, 240);
    this.scheduleReaderBrightness(win, 240);
  }

  private scheduleReaderBrightness(win: window.Window, delayMs: number): void {
    setTimeout(() => {
      applyReaderBrightnessFromSettings(win).catch(() => {});
    }, delayMs);
  }

  build() {
    Column() {
      if (this.themeRevision % 2 === 0) {
        ReaderHostScene()
      } else {
        ReaderHostScene()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
  }
}

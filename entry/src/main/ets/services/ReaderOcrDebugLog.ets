import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ReaderPageTranslation } from '../model/ReaderTranslationModels';
import { ehSettingsStore } from './EhSettingsStore';

export const READER_OCR_DEBUG_LOG_SETTING_KEY: string = 'reader_ocr_debug_log';

export interface ReaderOcrOverlayDebugItem {
  sourceText: string;
  translatedText: string;
  sourceX: number;
  sourceY: number;
  sourceWidth: number;
  sourceHeight: number;
  layoutX: number;
  layoutY: number;
  layoutWidth: number;
  layoutHeight: number;
  sourceFontSize: number;
  fontSize: number;
  lineHeight: number;
  estimatedLines: number;
}

const LOG_FILE_NAME: string = 'ehviewer_reader_ocr_debug.log';
const MAX_LOG_BYTES: number = 8 * 1024 * 1024;
const RETAINED_LOG_CHARACTERS: number = 2 * 1024 * 1024;

export class ReaderOcrDebugLog {
  private pendingBlocks: string[] = [];
  private overlaySnapshotKeys: string[] = [];
  private flushScheduled: boolean = false;
  private context: common.UIAbilityContext | undefined = undefined;

  recordRecognition(context: common.UIAbilityContext, gid: number, pageIndex: number, content: string): void {
    if (!this.isEnabled()) {
      return;
    }
    this.context = context;
    this.enqueue('\n================================================================================\n' +
      '类型：OCR识别与分组\n' +
      '时间：' + new Date().toISOString() + '\n' +
      'GID：' + gid.toString() + '\n' +
      '页码：' + (pageIndex + 1).toString() + '\n' + content.trim() + '\n', context);
  }

  recordOverlaySnapshot(translation: ReaderPageTranslation, displayWidth: number, displayHeight: number,
    items: ReaderOcrOverlayDebugItem[]): void {
    if (!this.isEnabled()) {
      return;
    }
    const key = translation.pageIndex.toString() + ':' + translation.updatedAt.toString() + ':' +
      Math.round(displayWidth).toString() + 'x' + Math.round(displayHeight).toString();
    if (this.overlaySnapshotKeys.indexOf(key) >= 0) {
      return;
    }
    this.overlaySnapshotKeys.push(key);
    if (this.overlaySnapshotKeys.length > 40) {
      this.overlaySnapshotKeys.splice(0, this.overlaySnapshotKeys.length - 40);
    }
    const lines: string[] = [];
    lines.push('\n================================================================================');
    lines.push('类型：覆盖层布局');
    lines.push('时间：' + new Date().toISOString());
    lines.push('页码：' + (translation.pageIndex + 1).toString());
    lines.push('OCR图像：' + translation.imageWidth.toString() + 'x' + translation.imageHeight.toString());
    lines.push('显示区域：' + roundDebugNumber(displayWidth) + 'x' + roundDebugNumber(displayHeight));
    for (let i = 0; i < items.length; i++) {
      lines.push('项目 ' + (i + 1).toString() + '：');
      lines.push('  原文=' + JSON.stringify(items[i].sourceText));
      lines.push('  译文=' + JSON.stringify(items[i].translatedText));
      lines.push('  源框=' + debugRect(items[i].sourceX, items[i].sourceY, items[i].sourceWidth,
        items[i].sourceHeight));
      lines.push('  布局框=' + debugRect(items[i].layoutX, items[i].layoutY, items[i].layoutWidth,
        items[i].layoutHeight));
      lines.push('  文本布局=原图缩放字号 ' + roundDebugNumber(items[i].sourceFontSize) + '，实际字号 ' +
        roundDebugNumber(items[i].fontSize) + '，行高 ' +
        roundDebugNumber(items[i].lineHeight) + '，预计 ' + items[i].estimatedLines.toString() + ' 行');
      lines.push('  位移=(' + roundDebugNumber(items[i].layoutX - items[i].sourceX) + ',' +
        roundDebugNumber(items[i].layoutY - items[i].sourceY) + ')');
    }
    this.enqueue(lines.join('\n') + '\n');
  }

  read(context: common.UIAbilityContext): string {
    if (!this.isEnabled()) {
      this.clear(context);
      return '';
    }
    this.flush(context);
    try {
      return fs.readTextSync(this.logPath(context));
    } catch (error) {
      return '';
    }
  }

  clear(context?: common.UIAbilityContext): void {
    this.pendingBlocks.splice(0, this.pendingBlocks.length);
    this.overlaySnapshotKeys.splice(0, this.overlaySnapshotKeys.length);
    this.flushScheduled = false;
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    const activeContext = targetContext === undefined ? this.context : targetContext;
    if (activeContext === undefined) {
      return;
    }
    try {
      fs.unlinkSync(this.logPath(activeContext));
    } catch (error) {
    }
  }

  private enqueue(block: string, context?: common.UIAbilityContext): void {
    this.pendingBlocks.push(block);
    if (this.flushScheduled) {
      return;
    }
    this.flushScheduled = true;
    setTimeout(() => {
      this.flushScheduled = false;
      this.flush(context);
    }, 0);
  }

  private flush(context?: common.UIAbilityContext): void {
    if (this.pendingBlocks.length === 0) {
      return;
    }
    const storedContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    const targetContext = storedContext === undefined ? this.context : storedContext;
    if (targetContext === undefined) {
      return;
    }
    const content = this.pendingBlocks.join('');
    if (this.append(targetContext, content)) {
      this.pendingBlocks.splice(0, this.pendingBlocks.length);
    }
  }

  private append(context: common.UIAbilityContext, content: string): boolean {
    const path = this.logPath(context);
    let fd = -1;
    try {
      let replacement = '';
      try {
        const stat = fs.statSync(path);
        if (stat.size + content.length > MAX_LOG_BYTES) {
          const existing = fs.readTextSync(path);
          const start = Math.max(0, existing.length - RETAINED_LOG_CHARACTERS);
          replacement = '[较早的OCR调试记录已因日志大小限制被移除]\n' + existing.substring(start) + content;
        }
      } catch (error) {
      }
      const mode = replacement.length > 0 ?
        fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE :
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND;
      const file = fs.openSync(path, mode);
      fd = file.fd;
      fs.writeSync(fd, replacement.length > 0 ? replacement : content);
      return true;
    } catch (error) {
      return false;
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (error) {
        }
      }
    }
  }

  private logPath(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + LOG_FILE_NAME;
  }

  private isEnabled(): boolean {
    return ehSettingsStore.getValue(READER_OCR_DEBUG_LOG_SETTING_KEY, 'Off') === 'On';
  }
}

export const readerOcrDebugLog: ReaderOcrDebugLog = new ReaderOcrDebugLog();

function roundDebugNumber(value: number): string {
  return (Math.round(value * 10) / 10).toString();
}

function debugRect(x: number, y: number, width: number, height: number): string {
  return '(' + roundDebugNumber(x) + ',' + roundDebugNumber(y) + ',' + roundDebugNumber(width) + ',' +
    roundDebugNumber(height) + ')';
}

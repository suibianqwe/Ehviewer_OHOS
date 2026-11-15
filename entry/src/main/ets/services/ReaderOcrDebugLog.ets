import { common } from '@kit.AbilityKit';
import { DiagnosticLogFile } from './DiagnosticLogFile';
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
  vertical: boolean;
  columnCount: number;
}

const LOG_FILE_NAME: string = 'ehviewer_reader_ocr_debug.log';
const MAX_LOG_BYTES: number = 8 * 1024 * 1024;

export class ReaderOcrDebugLog {
  private file: DiagnosticLogFile = new DiagnosticLogFile(LOG_FILE_NAME, MAX_LOG_BYTES);
  private overlaySnapshotKeys: string[] = [];
  private context: common.UIAbilityContext | undefined = undefined;

  recordRecognition(context: common.UIAbilityContext, gid: number, pageIndex: number, content: string): void {
    if (!this.isEnabled()) {
      return;
    }
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
        roundDebugNumber(items[i].lineHeight) + '，方向 ' + (items[i].vertical ? '竖排' : '横排') + '，预计 ' +
        items[i].estimatedLines.toString() + (items[i].vertical ?
          ' 行 / ' + items[i].columnCount.toString() + ' 列' : ' 行'));
      lines.push('  位移=(' + roundDebugNumber(items[i].layoutX - items[i].sourceX) + ',' +
        roundDebugNumber(items[i].layoutY - items[i].sourceY) + ')');
    }
    this.enqueue(lines.join('\n') + '\n');
  }

  async read(context: common.UIAbilityContext): Promise<string> {
    if (!this.isEnabled()) {
      await this.clear(context);
      return '';
    }
    return this.file.read(context.filesDir);
  }

  clear(context?: common.UIAbilityContext): Promise<void> {
    this.overlaySnapshotKeys.splice(0, this.overlaySnapshotKeys.length);
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    const activeContext = targetContext ?? this.context;
    return activeContext === undefined ? Promise.resolve() : this.file.clear(activeContext.filesDir);
  }

  private enqueue(block: string, context?: common.UIAbilityContext): void {
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    this.context = targetContext ?? this.context;
    if (this.context !== undefined) this.file.append(this.context.filesDir, block);
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

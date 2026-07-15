import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ehSettingsStore } from './EhSettingsStore';

export const AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY: string = 'translation_ai_conversation_log';

const LOG_FILE_NAME: string = 'ehviewer_ai_translation.log';
const MAX_LOG_BYTES: number = 16 * 1024 * 1024;
const RETAINED_LOG_CHARACTERS: number = 4 * 1024 * 1024;

export class AiTranslationConversationLog {
  private pendingBlocks: string[] = [];
  private activeConversationIds: string[] = [];
  private flushScheduled: boolean = false;
  private sequence: number = 0;

  recordRequest(provider: string, model: string, endpoint: string, requestBody: string): string {
    if (!this.isEnabled()) {
      return '';
    }
    this.sequence++;
    const now = new Date();
    const id = now.getTime().toString(36) + '-' + this.sequence.toString(36);
    this.activeConversationIds.push(id);
    this.enqueue('\n================================================================================\n' +
      '会话编号：' + id + '\n' +
      '发送时间：' + now.toISOString() + '\n' +
      '服务：' + provider + '\n' +
      '模型：' + model + '\n' +
      '接口：' + endpointWithoutQuery(endpoint) + '\n' +
      '[发送给 AI]\n' + requestBody + '\n');
    return id;
  }

  recordResponse(id: string, content: string, status: string = '完成'): void {
    if (id.length === 0 || !this.isEnabled() || !this.consumeConversation(id)) {
      return;
    }
    this.enqueue('会话编号：' + id + '\n' +
      '返回时间：' + new Date().toISOString() + '\n' +
      '状态：' + status + '\n' +
      '[AI 返回]\n' + content + '\n');
  }

  recordError(id: string, error: string): void {
    if (id.length === 0 || !this.isEnabled() || !this.consumeConversation(id)) {
      return;
    }
    this.enqueue('会话编号：' + id + '\n' +
      '返回时间：' + new Date().toISOString() + '\n' +
      '状态：失败\n' +
      '[请求错误]\n' + error + '\n');
  }

  read(context: common.UIAbilityContext): string {
    this.flush(context);
    try {
      return fs.readTextSync(this.logPath(context));
    } catch (error) {
      return '';
    }
  }

  clear(context?: common.UIAbilityContext): void {
    this.pendingBlocks.splice(0, this.pendingBlocks.length);
    this.activeConversationIds.splice(0, this.activeConversationIds.length);
    this.flushScheduled = false;
    this.sequence = 0;
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    if (targetContext === undefined) {
      return;
    }
    try {
      fs.unlinkSync(this.logPath(targetContext));
    } catch (error) {
    }
  }

  private enqueue(block: string): void {
    this.pendingBlocks.push(block);
    if (this.flushScheduled) {
      return;
    }
    this.flushScheduled = true;
    setTimeout(() => {
      this.flushScheduled = false;
      this.flush();
    }, 0);
  }

  private flush(context?: common.UIAbilityContext): void {
    if (this.pendingBlocks.length === 0) {
      return;
    }
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
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
          let retained = existing.length > RETAINED_LOG_CHARACTERS ?
            existing.substring(existing.length - RETAINED_LOG_CHARACTERS) : existing;
          const entryStart = retained.indexOf('\n================================================================================\n');
          if (entryStart >= 0) {
            retained = retained.substring(entryStart);
          }
          replacement = '[较早的 AI 翻译记录已因日志大小限制被移除]\n' + retained + content;
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
    return ehSettingsStore.getValue(AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY, 'Off') === 'On';
  }

  private consumeConversation(id: string): boolean {
    const index = this.activeConversationIds.indexOf(id);
    if (index < 0) {
      return false;
    }
    this.activeConversationIds.splice(index, 1);
    return true;
  }
}

export const aiTranslationConversationLog: AiTranslationConversationLog = new AiTranslationConversationLog();

function endpointWithoutQuery(endpoint: string): string {
  const query = endpoint.indexOf('?');
  const fragment = endpoint.indexOf('#');
  let end = endpoint.length;
  if (query >= 0) {
    end = Math.min(end, query);
  }
  if (fragment >= 0) {
    end = Math.min(end, fragment);
  }
  return endpoint.substring(0, end);
}

import { common } from '@kit.AbilityKit';
import { DiagnosticLogFile } from './DiagnosticLogFile';
import { ehSettingsStore } from './EhSettingsStore';

export const AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY: string = 'translation_ai_conversation_log';

const LOG_FILE_NAME: string = 'ehviewer_ai_translation.log';
const MAX_LOG_BYTES: number = 16 * 1024 * 1024;

export class AiTranslationConversationLog {
  private file: DiagnosticLogFile = new DiagnosticLogFile(LOG_FILE_NAME, MAX_LOG_BYTES);
  private activeConversationIds: string[] = [];
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

  async read(context: common.UIAbilityContext): Promise<string> {
    if (!this.isEnabled()) {
      await this.clear(context);
      return '';
    }
    return this.file.read(context.filesDir);
  }

  clear(context?: common.UIAbilityContext): Promise<void> {
    this.activeConversationIds.splice(0, this.activeConversationIds.length);
    this.sequence = 0;
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    return targetContext === undefined ? Promise.resolve() : this.file.clear(targetContext.filesDir);
  }

  private enqueue(block: string, context?: common.UIAbilityContext): void {
    const targetContext = context === undefined ? AppStorage.get<common.UIAbilityContext>('abilityContext') : context;
    if (targetContext !== undefined) this.file.append(targetContext.filesDir, block);
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

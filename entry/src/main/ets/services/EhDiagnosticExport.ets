import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { taskpool } from '@kit.ArkTS';
import { ehAppLog } from './EhAppLog';
import { ehFaultLogStore } from './EhFaultLogStore';
import { ehParseErrorBodyStore } from './EhParseErrorBodyStore';
import { aiTranslationConversationLog } from './AiTranslationConversationLog';
import { readerOcrDebugLog } from './ReaderOcrDebugLog';
import { DiagnosticLogFile, readDiagnosticFile } from './DiagnosticLogFile';
import { redactDiagnosticExportTask } from './DiagnosticExportTask';
import { ehSettingsStore } from './EhSettingsStore';
import { EH_APP_VERSION_CODE, EH_APP_VERSION_NAME, EH_TARGET_PLATFORM } from './EhBuildInfo';

const DIAGNOSTIC_SETTINGS: string[] = ['gallery_site', 'proxy', 'proxy_socks_dns', 'dns_over_https',
  'dns_over_https_provider', 'domain_fronting', 'auto_direct_connection', 'built_in_hosts', 'built_ex_hosts',
  'download_thread', 'download_timeout', 'preload_image', 'reading_direction', 'page_scaling',
  'adaptive_dual_page', 'image_size', 'download_origin_image', 'save_crash_log', 'save_parse_error_body',
  'reader_image_super_resolution', 'reader_super_resolution_engine', 'reader_sdr_to_hdr',
  'reader_ocr_debug_log', 'translation_ai_conversation_log'];

class EhDiagnosticExport {
  private networkLog: DiagnosticLogFile = new DiagnosticLogFile('ehviewer_network.log', 512 * 1024);

  async rememberNetwork(context: common.UIAbilityContext, content: string): Promise<void> {
    await this.networkLog.replace(context.filesDir, content);
  }

  async create(context: common.UIAbilityContext, kind: string = 'all'): Promise<string> {
    const lines: string[] = ['EhViewer OHOS Diagnostic Log', 'ExportedAt ' + new Date().toISOString(),
      'Version ' + EH_APP_VERSION_NAME + ' (' + EH_APP_VERSION_CODE.toString() + ')', 'Target ' + EH_TARGET_PLATFORM,
      'Device ' + deviceInfo.productModel, 'DeviceType ' + deviceInfo.deviceType,
      'System ' + deviceInfo.osFullName, 'DisplayVersion ' + deviceInfo.displayVersion,
      'API ' + deviceInfo.sdkApiVersion.toString(), '\n[Diagnostic settings]'];
    for (const key of DIAGNOSTIC_SETTINGS) lines.push(key + ' = ' + ehSettingsStore.getValue(key, '(unset)'));
    lines.push('\n' + await ehFaultLogStore.read());
    await this.section(lines, 'App Log', () => ehAppLog.read(context));
    await this.section(lines, 'Latest Network Diagnostics', () => this.networkLog.read(context.filesDir));
    if (kind === 'all' || kind === 'ai') {
      await this.section(lines, 'AI Translation Records', () => aiTranslationConversationLog.read(context));
    }
    if (kind === 'all' || kind === 'ocr') {
      await this.section(lines, 'Comic OCR Debug Records', () => readerOcrDebugLog.read(context));
    }
    lines.push('\n[Parse Error Bodies]');
    try {
      const entries = await ehParseErrorBodyStore.list(context);
      let remaining = 10 * 1024 * 1024;
      if (entries.length === 0) lines.push('(none)');
      for (const entry of entries) {
        if (remaining <= 0) { lines.push('[Additional bodies omitted due to export size limit]'); break; }
        lines.push('\n[Parse body ' + entry.name + ']');
        lines.push('Size ' + entry.size.toString() + ' bytes');
        await this.section(lines, 'Response body', () => readDiagnosticFile(entry.path, Math.min(remaining, 4 * 1024 * 1024)));
        remaining -= Math.min(entry.size, 4 * 1024 * 1024);
      }
    } catch (error) { lines.push('[Parse bodies unavailable] ' + String(error)); }
    return await taskpool.execute(redactDiagnosticExportTask, lines.join('\n') + '\n') as string;
  }

  async clear(context: common.UIAbilityContext): Promise<void> {
    await Promise.all([ehAppLog.clear(context), ehParseErrorBodyStore.clear(context), ehFaultLogStore.clear(),
      this.networkLog.clear(context.filesDir), aiTranslationConversationLog.clear(context), readerOcrDebugLog.clear(context)]);
  }

  private async section(lines: string[], name: string, read: () => Promise<string>): Promise<void> {
    lines.push('\n[' + name + ']');
    try {
      const text = await read();
      lines.push(text.trim().length > 0 ? text : '(none saved)');
    } catch (error) { lines.push('[Section unavailable] ' + String(error)); }
  }
}

export const ehDiagnosticExport: EhDiagnosticExport = new EhDiagnosticExport();

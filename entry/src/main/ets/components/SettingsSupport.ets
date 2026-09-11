import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  DOWNLOAD_LOCATION_APP_FILES,
  DOWNLOAD_LOCATION_DOWNLOADS,
} from '../services/EhDownloadFileStore';
import {
  ehSettingsStore,
} from '../services/EhSettingsStore';
import {
  socks5ProxySupported,
} from '../services/EhNetworkConfig';
import {
  AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY,
} from '../services/AiTranslationConversationLog';
import { SettingsRowItem, uiText, uiValue, padTwo, normalizeProxyOption, normalizeAutoTransferTimeOption, normalizeBrightnessLevelOption } from '../shared/EhShared';

export const DIAGNOSTIC_LOG_TAG: string = 'SettingsScene';
export const LOG_EXPORT_CHUNK_BYTES: number = 64 * 1024;
export const EH_LICENSE_URL: string = 'https://github.com/suibianqwe/Ehviewer_OHOS/blob/main/LICENSE';
export function settingsRowActionText(row: SettingsRowItem): string {
  if (row.value.length > 0) {
    return uiValue(row.value);
  }
  return uiText('Open');
}

export function isSecretSettingKey(key: string | undefined): boolean {
  return key === 'proxy_password' || key === 'translation_deepseek_api_key' ||
    key === 'translation_openai_api_key' || key === 'translation_official_openai_api_key' ||
    key === 'translation_custom_api_key' || key === 'translation_gemini_api_key';
}

export function isDirectTranslationApiKey(key: string): boolean {
  return key === 'translation_deepseek_api_key' || key === 'translation_official_openai_api_key' ||
    key === 'translation_gemini_api_key';
}

export function cleanErrorMessage(error: Error): string {
  let message = error.message.length > 0 ? error.message : String(error);
  while (message.indexOf('Error: ') === 0) {
    message = message.substring('Error: '.length);
  }
  return message;
}

export function isCustomTranslationApiField(key: string): boolean {
  return key === 'translation_custom_api_name' || key === 'translation_custom_api_base_url' ||
    key === 'translation_custom_api_key' || key === 'translation_custom_api_model';
}

export function isTranslationSettingKey(key: string): boolean {
  return key.indexOf('translation_') === 0 && key !== AI_TRANSLATION_CONVERSATION_LOG_SETTING_KEY;
}

export function settingsSliderNumberValue(row: SettingsRowItem): number {
  if (row.key === 'start_transfer_time') {
    return Number.parseInt(normalizeAutoTransferTimeOption(row.value));
  }
  if (row.key === 'screen_lightness') {
    return Number.parseInt(normalizeBrightnessLevelOption(row.value));
  }
  return 0;
}

export function settingsSliderMin(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' ? 1 : 0;
}

export function settingsSliderMax(row: SettingsRowItem): number {
  return row.key === 'start_transfer_time' ? 20 : 100;
}

export function settingsSliderTextValue(row: SettingsRowItem, value: number): string {
  if (row.key === 'start_transfer_time') {
    return normalizeAutoTransferTimeOption(Math.max(1, Math.min(20, Math.round(value))).toString() + 's');
  }
  return normalizeBrightnessLevelOption(Math.max(0, Math.min(100, Math.round(value))).toString() + '%');
}

export function settingsSliderDisplayText(row: SettingsRowItem, value: number): string {
  return uiValue(settingsSliderTextValue(row, value));
}

export function normalizeSettingsDownloadLocation(value: string): string {
  return value === DOWNLOAD_LOCATION_DOWNLOADS ? DOWNLOAD_LOCATION_DOWNLOADS : DOWNLOAD_LOCATION_APP_FILES;
}

export function diagnosticTimestamp(now: Date): string {
  return now.getFullYear().toString() + padTwo(now.getMonth() + 1) + padTwo(now.getDate()) + '_' +
    padTwo(now.getHours()) + padTwo(now.getMinutes()) + padTwo(now.getSeconds());
}

export async function pickDownloadsOutputPath(context: common.UIAbilityContext, fileName: string): Promise<string> {
  const saveOptions = new picker.DocumentSaveOptions();
  saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
  const documentPicker = new picker.DocumentViewPicker(context);
  const result = await documentPicker.save(saveOptions);
  if (result.length === 0 || result[0].length === 0) {
    return '';
  }
  return new fileUri.FileUri(result[0] + '/' + sanitizeExportFileName(fileName)).path;
}

export function sanitizeExportFileName(fileName: string): string {
  return fileName.replace(/[\\/:*?"<>|]/g, '_');
}

export async function writeTextFileChunked(path: string, content: string): Promise<void> {
  let fd = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
    fd = file.fd;
    for (let start = 0; start < content.length; start += LOG_EXPORT_CHUNK_BYTES) {
      fs.writeSync(fd, content.substring(start, Math.min(content.length, start + LOG_EXPORT_CHUNK_BYTES)));
      await yieldToUi();
    }
  } catch (error) {
    removeFileQuietly(path);
    throw new Error(String(error));
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (error) {
      }
    }
  }
}

export function removeFileQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
  }
}

export function yieldToUi(): Promise<void> {
  return new Promise<void>((resolve: (value: void | PromiseLike<void>) => void) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}

export function settingsRowRenderKey(row: SettingsRowItem): string {
  if (row.type === 'slider') {
    return row.title + ':' + row.type;
  }
  return row.title + ':' + row.value + ':' + row.type;
}

export function isNetworkSettingKey(key: string): boolean {
  return key === 'proxy' || key === 'proxy_host' || key === 'proxy_port' || key === 'proxy_username' ||
    key === 'proxy_password' || key === 'proxy_exclusion_list' || key === 'proxy_socks_dns' ||
    key === 'built_in_hosts' ||
    key === 'built_ex_hosts' || key === 'dns_over_https' || key === 'dns_over_https_provider' ||
    key === 'domain_fronting' ||
    key === 'auto_direct_connection' || key === 'gallery_site';
}

export function normalizeProxyExclusionListText(value: string): string {
  const parts = value.split(',');
  const result: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const item = parts[i].trim();
    if (item.length > 0 && result.indexOf(item) < 0) {
      result.push(item);
    }
  }
  return result.join(',');
}

export function proxyDiagnosticText(): string {
  const proxy = normalizeProxyOption(ehSettingsStore.getValue('proxy', 'System'));
  if (proxy !== 'HTTP' && proxy !== 'SOCKS') {
    return proxy;
  }
  const host = ehSettingsStore.getValue('proxy_host', '').trim();
  const port = ehSettingsStore.getValue('proxy_port', '').trim();
  const username = ehSettingsStore.getValue('proxy_username', '').trim();
  const exclusions = ehSettingsStore.getValue('proxy_exclusion_list', '').trim();
  let text = proxy + ' ' + (host.length > 0 ? host : '(missing host)') + ':' +
    (port.length > 0 ? port : '(missing port)');
  if (username.length > 0) {
    text += ' user=' + username + ' password=***';
  }
  if (exclusions.length > 0) {
    text += ' exclusions=' + exclusions;
  }
  if (proxy === 'SOCKS') {
    text += ' dns=' + ehSettingsStore.getValue('proxy_socks_dns', 'Proxy');
    if (!socks5ProxySupported()) {
      text += ' unavailable(api<26)';
    }
  }
  return text;
}

export function settingDisplayValueForStatus(key: string, value: string): string {
  if (isSecretSettingKey(key) && value.length > 0) {
    return '***';
  }
  return value;
}



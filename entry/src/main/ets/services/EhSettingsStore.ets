import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  SavedTranslationApi,
  parseSavedTranslationApis,
  serializeSavedTranslationApis,
  uniqueTranslationApiName
} from './TranslationApiConfigSupport';

const PREFERENCES_NAME: string = 'ehviewer_settings';
const VALUES_KEY: string = 'values';
export const HISTORY_INFO_SIZE_KEY: string = 'history_info_size';
export const DEFAULT_HISTORY_INFO_SIZE: string = '100';
export const TRANSLATION_BUTTONS_VISIBLE_KEY: string = 'ehviewer_translation_buttons_visible';
const HISTORY_INFO_SIZE_OPTIONS: string[] = ['100', '500', '1000', '5000', '10000', '20000'];

export interface SettingEntry {
  key: string;
  value: string;
}

interface StoredSettingEntry {
  key?: string;
  value?: string;
}

export function defaultSettingEntries(): SettingEntry[] {
  return [
    { key: 'gallery_site', value: 'E-Hentai' },
    { key: 'use_account_default_filter', value: 'On' },
    { key: 'follow_system_dark_mode', value: 'Off' },
    { key: 'theme', value: 'Light' },
    { key: 'launch_page', value: 'Homepage' },
    { key: 'list_mode', value: 'Detail' },
    { key: 'detail_size', value: 'Medium' },
    { key: 'thumb_size', value: 'Medium' },
    { key: HISTORY_INFO_SIZE_KEY, value: DEFAULT_HISTORY_INFO_SIZE },
    { key: 'show_jpn_title', value: 'Off' },
    { key: 'default_fav_slot', value: 'Ask' },
    { key: 'show_gallery_pages', value: 'Off' },
    { key: 'show_gallery_rating', value: 'On' },
    { key: 'show_gallery_language', value: 'On' },
    { key: 'show_tag_translations', value: 'On' },
    { key: 'split_screen_mode', value: 'On' },
    { key: 'split_screen_ratio', value: '0.42' },
    { key: 'show_eh_limits', value: 'On' },
    { key: 'translation_buttons_enabled', value: 'On' },
    { key: 'translation_provider', value: 'Google Web' },
    { key: 'translation_target_language', value: 'Simplified Chinese' },
    { key: 'translation_timeout', value: '15s' },
    { key: 'translation_deepseek_api_key', value: '' },
    { key: 'translation_deepseek_model', value: 'deepseek-v4-flash' },
    { key: 'translation_openai_api_key', value: '' },
    { key: 'translation_openai_base_url', value: 'https://api.openai.com/v1' },
    { key: 'translation_openai_model', value: 'gpt-4o-mini' },
    { key: 'translation_official_openai_api_key', value: '' },
    { key: 'translation_official_openai_model', value: 'gpt-4.1-mini' },
    { key: 'translation_gemini_api_key', value: '' },
    { key: 'translation_gemini_model', value: 'gemini-3.5-flash' },
    { key: 'translation_custom_apis', value: '[]' },
    { key: 'translation_custom_api_selected', value: '' },
    { key: 'cellular_network_warning', value: 'Off' },
    { key: 'screen_rotation', value: 'Default' },
    { key: 'reading_direction', value: 'Right to left' },
    { key: 'page_scaling', value: 'Fit screen' },
    { key: 'start_position', value: 'Top right' },
    { key: 'start_transfer_time', value: '5s' },
    { key: 'reader_standalone', value: 'On' },
    { key: 'keep_screen_on', value: 'Off' },
    { key: 'gallery_show_clock', value: 'On' },
    { key: 'gallery_show_progress', value: 'On' },
    { key: 'gallery_show_battery', value: 'On' },
    { key: 'volume_page', value: 'Off' },
    { key: 'reading_fullscreen', value: 'On' },
    { key: 'reader_background', value: 'Deep gray' },
    { key: 'screen_lightness', value: '50%' },
    { key: 'custom_screen_lightness', value: 'Off' },
    { key: 'ultra_dark_mode', value: 'Off' },
    { key: 'ultra_dark_lightness', value: '50%' },
    { key: 'download_location', value: 'App files' },
    { key: 'download_thread', value: '3' },
    { key: 'preload_image', value: '5' },
    { key: 'download_list_pagination', value: 'On' },
    { key: 'image_size', value: 'Auto' },
    { key: 'download_origin_image', value: 'Off' },
    { key: 'download_timeout', value: '30s' },
    { key: 'download_order_asc', value: 'On' },
    { key: 'pattern_protection', value: 'Off' },
    { key: 'enable_secure', value: 'Off' },
    { key: 'save_parse_error_body', value: 'Off' },
    { key: 'save_crash_log', value: 'Off' },
    { key: 'read_cache_size', value: '160 MB' },
    { key: 'app_language', value: 'System' },
    { key: 'proxy', value: 'System' },
    { key: 'proxy_host', value: '' },
    { key: 'proxy_port', value: '' },
    { key: 'proxy_username', value: '' },
    { key: 'proxy_password', value: '' },
    { key: 'proxy_exclusion_list', value: '' },
    { key: 'built_in_hosts', value: 'Off' },
    { key: 'built_ex_hosts', value: 'Off' },
    { key: 'dns_over_https', value: 'Off' },
    { key: 'domain_fronting', value: 'Off' },
    { key: 'auto_direct_connection', value: 'Off' },
    { key: 'close_auto_updates', value: 'Off' },
    { key: 'network_defaults_20260612', value: 'Applied' },
    { key: 'network_runtime_20260613', value: 'Applied' },
    { key: 'network_proxy_20260613', value: 'Applied' },
    { key: 'network_proxy_20260707', value: 'Applied' },
    { key: 'network_passthrough_20260714', value: 'Applied' }
  ];
}

export class EhSettingsStore {
  private entries: SettingEntry[] = defaultSettingEntries();
  private loaded: boolean = false;
  private ensurePromise: Promise<void> | null = null;

  getEntries(): SettingEntry[] {
    return cloneEntries(this.entries);
  }

  getValue(key: string, fallback: string = ''): string {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].key === key) {
        return this.entries[i].value;
      }
    }
    return fallback;
  }

  setValue(key: string, value: string): void {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].key === key) {
        this.entries[i].value = value;
        if (key === 'translation_buttons_enabled') {
          this.syncTranslationButtonVisibility();
        }
        return;
      }
    }
    this.entries.push({ key: key, value: value });
    if (key === 'translation_buttons_enabled') {
      this.syncTranslationButtonVisibility();
    }
  }

  syncTranslationButtonVisibility(): void {
    AppStorage.setOrCreate<boolean>(TRANSLATION_BUTTONS_VISIBLE_KEY,
      this.getValue('translation_buttons_enabled', 'On') === 'On');
  }

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      return;
    }
    if (this.ensurePromise !== null) {
      await this.ensurePromise;
      return;
    }
    this.ensurePromise = this.load(context);
    try {
      await this.ensurePromise;
      this.loaded = true;
    } finally {
      this.ensurePromise = null;
    }
  }

  async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      this.entries = defaultSettingEntries();
      if (typeof raw !== 'string' || raw.length === 0) {
        return;
      }

      const parsed = JSON.parse(raw) as StoredSettingEntry[];
      if (!Array.isArray(parsed)) {
        return;
      }

      let hasNetworkMigration = false;
      let hasRuntimeMigration = false;
      let hasProxyMigration = false;
      let hasProxyApi24Migration = false;
      let hasPassthroughMigration = false;
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i];
        if (typeof item.key === 'string' && typeof item.value === 'string') {
          if (item.key === 'network_defaults_20260612') {
            hasNetworkMigration = true;
          }
          if (item.key === 'network_runtime_20260613') {
            hasRuntimeMigration = true;
          }
          if (item.key === 'network_proxy_20260613') {
            hasProxyMigration = true;
          }
          if (item.key === 'network_proxy_20260707') {
            hasProxyApi24Migration = true;
          }
          if (item.key === 'network_passthrough_20260714') {
            hasPassthroughMigration = true;
          }
          this.setValue(item.key, item.value);
        }
      }

      if (!hasNetworkMigration) {
        this.setValue('built_in_hosts', 'On');
        this.setValue('built_ex_hosts', 'On');
        this.setValue('network_defaults_20260612', 'Applied');
      }
      if (!hasRuntimeMigration) {
        this.setValue('network_runtime_20260613', 'Applied');
      }
      if (!hasProxyMigration) {
        if (this.getValue('proxy', 'System') === 'Off') {
          this.setValue('proxy', 'System');
        }
        this.setValue('network_proxy_20260613', 'Applied');
      }
      if (!hasProxyApi24Migration) {
        if (this.getValue('proxy', 'System') === 'SOCKS') {
          this.setValue('proxy', 'HTTP');
        }
        this.setValue('network_proxy_20260707', 'Applied');
      }
      if (!hasPassthroughMigration) {
        const legacyAutomaticNetworkConfig = hasNetworkMigration &&
          this.getValue('built_in_hosts', 'Off') === 'On' &&
          this.getValue('built_ex_hosts', 'Off') === 'On' &&
          this.getValue('dns_over_https', 'Off') === 'Off' &&
          this.getValue('domain_fronting', 'Off') === 'On' &&
          this.getValue('auto_direct_connection', 'Off') === 'On';
        if (legacyAutomaticNetworkConfig) {
          this.setValue('built_in_hosts', 'Off');
          this.setValue('built_ex_hosts', 'Off');
          this.setValue('domain_fronting', 'Off');
          this.setValue('auto_direct_connection', 'Off');
        }
        this.setValue('network_passthrough_20260714', 'Applied');
      }
      if (this.getValue('download_location', 'App files') !== 'Downloads') {
        this.setValue('download_location', 'App files');
      }
      if (this.getValue('download_timeout', '30s') === 'Default') {
        this.setValue('download_timeout', '30s');
      }
      if (this.getValue('detail_size', 'Medium') === 'Default') {
        this.setValue('detail_size', 'Medium');
      }
      if (this.getValue('detail_size', 'Medium') === 'Large') {
        this.setValue('detail_size', 'Loose');
      }
      this.migrateLegacyTranslationApi();
      if (!hasPassthroughMigration) {
        try {
          await prefs.put(VALUES_KEY, JSON.stringify(this.entries));
          await prefs.flush();
        } catch (error) {
        }
      }
    } catch (error) {
      throw new Error(String(error));
    } finally {
      this.syncTranslationButtonVisibility();
    }
  }

  private migrateLegacyTranslationApi(): void {
    const legacyProvider = this.getValue('translation_provider', 'Google Web');
    const legacyBaseUrl = this.getValue('translation_openai_base_url', 'https://api.openai.com/v1').trim();
    const legacyApiKey = this.getValue('translation_openai_api_key', '');
    const legacyModel = this.getValue('translation_openai_model', 'gpt-4o-mini').trim();
    const items = parseSavedTranslationApis(this.getValue('translation_custom_apis', '[]'));
    if (items.length === 0 && (legacyProvider === 'OpenAI compatible' || legacyApiKey.length > 0 ||
      legacyBaseUrl !== 'https://api.openai.com/v1')) {
      const name = uniqueTranslationApiName(items, 'Imported API');
      const imported: SavedTranslationApi = {
        name: name,
        baseUrl: legacyBaseUrl.length > 0 ? legacyBaseUrl : 'https://api.openai.com/v1',
        apiKey: legacyApiKey,
        model: legacyModel
      };
      items.push(imported);
      this.setValue('translation_custom_apis', serializeSavedTranslationApis(items));
      this.setValue('translation_custom_api_selected', name);
    }
    if (legacyProvider === 'OpenAI compatible') {
      this.setValue('translation_provider', 'Custom API');
    }
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(this.entries));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }
}

export function historyInfoSizeOptions(): string[] {
  return HISTORY_INFO_SIZE_OPTIONS.slice();
}

export function normalizeHistoryInfoSizeOption(value: string): string {
  const size = Number.parseInt(value);
  if (Number.isNaN(size)) {
    return DEFAULT_HISTORY_INFO_SIZE;
  }
  if (size <= 100) {
    return '100';
  }
  if (size <= 500) {
    return '500';
  }
  if (size <= 1000) {
    return '1000';
  }
  if (size <= 5000) {
    return '5000';
  }
  if (size <= 10000) {
    return '10000';
  }
  return '20000';
}

export function historyInfoSizeLimitFromValue(value: string): number {
  return Number.parseInt(normalizeHistoryInfoSizeOption(value));
}

function cloneEntries(entries: SettingEntry[]): SettingEntry[] {
  const cloned: SettingEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    cloned.push({ key: entries[i].key, value: entries[i].value });
  }
  return cloned;
}

export const ehSettingsStore: EhSettingsStore = new EhSettingsStore();

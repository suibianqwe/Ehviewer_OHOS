import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'ehviewer_settings';
const VALUES_KEY: string = 'values';

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
    { key: 'theme', value: 'Light' },
    { key: 'launch_page', value: 'Homepage' },
    { key: 'list_mode', value: 'Detail' },
    { key: 'detail_size', value: 'Default' },
    { key: 'thumb_size', value: 'Medium' },
    { key: 'show_jpn_title', value: 'Off' },
    { key: 'show_gallery_pages', value: 'Off' },
    { key: 'show_tag_translations', value: 'On' },
    { key: 'show_eh_limits', value: 'On' },
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
    { key: 'screen_lightness', value: '50%' },
    { key: 'custom_screen_lightness', value: 'Off' },
    { key: 'ultra_dark_mode', value: 'Off' },
    { key: 'ultra_dark_lightness', value: '50%' },
    { key: 'download_location', value: 'App files' },
    { key: 'media_scan', value: 'Off' },
    { key: 'download_thread', value: '3' },
    { key: 'preload_image', value: '5' },
    { key: 'download_list_pagination', value: 'On' },
    { key: 'image_size', value: 'Auto' },
    { key: 'download_origin_image', value: 'Off' },
    { key: 'download_timeout', value: 'Default' },
    { key: 'download_order_asc', value: 'On' },
    { key: 'enable_secure', value: 'Off' },
    { key: 'enable_analytics', value: 'Off' },
    { key: 'save_parse_error_body', value: 'Off' },
    { key: 'save_crash_log', value: 'Off' },
    { key: 'read_cache_size', value: '160 MB' },
    { key: 'app_language', value: 'System' },
    { key: 'proxy', value: 'System' },
    { key: 'proxy_host', value: '' },
    { key: 'proxy_port', value: '' },
    { key: 'built_in_hosts', value: 'On' },
    { key: 'built_ex_hosts', value: 'On' },
    { key: 'dns_over_https', value: 'Off' },
    { key: 'domain_fronting', value: 'On' },
    { key: 'close_auto_updates', value: 'Off' },
    { key: 'network_defaults_20260612', value: 'Applied' },
    { key: 'network_runtime_20260613', value: 'Applied' },
    { key: 'network_proxy_20260613', value: 'Applied' }
  ];
}

export class EhSettingsStore {
  private entries: SettingEntry[] = defaultSettingEntries();

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
        return;
      }
    }
    this.entries.push({ key: key, value: value });
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
      if (this.getValue('download_location', 'App files') !== 'Downloads') {
        this.setValue('download_location', 'App files');
      }
    } catch (error) {
      throw new Error(String(error));
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

function cloneEntries(entries: SettingEntry[]): SettingEntry[] {
  const cloned: SettingEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    cloned.push({ key: entries[i].key, value: entries[i].value });
  }
  return cloned;
}

export const ehSettingsStore: EhSettingsStore = new EhSettingsStore();

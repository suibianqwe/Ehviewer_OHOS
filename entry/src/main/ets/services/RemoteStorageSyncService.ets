import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ehBookmarkStore, SearchBookmarkBackupInfo } from './EhBookmarkStore';
import { ehBrowsePositionStore, BrowsePositionsBackupInfo } from './EhBrowsePositionStore';
import { ehCommentBlacklistStore, CommentBlacklistBackupEntry } from './EhCommentBlacklistStore';
import { ehFilterStore } from './EhFilterStore';
import { ehHistoryStore, ReadingProgressBackupInfo } from './EhHistoryStore';
import { ehSearchHistoryStore } from './EhSearchHistoryStore';
import { ehSettingsStore, HISTORY_INFO_SIZE_KEY, historyInfoSizeLimitFromValue, SettingEntry } from './EhSettingsStore';
import { REMOTE_STORAGE_PURPOSE_SYNC, RemoteStorageProfile, remoteStorageProfileStore } from './RemoteStorageProfiles';
import { logRemoteStorageError, logRemoteStorageInfo, logRemoteStorageWarn } from './RemoteStorageLog';
import { WebDavClient } from './WebDavClient';
import { GalleryInfo } from '../model/GalleryModels';

export const REMOTE_SYNC_STATUS_TEXT_KEY: string = 'remoteSyncStatusText';
export const REMOTE_SYNC_STATUS_DETAIL_KEY: string = 'remoteSyncStatusDetail';
export const REMOTE_SYNC_STATUS_REVISION_KEY: string = 'remoteSyncStatusRevision';

const PREFERENCES_NAME: string = 'ehviewer_remote_sync';
const LAST_SYNC_KEY: string = 'lastSyncAt';
const LAST_PULL_KEY: string = 'lastPulledAt';
const FINGERPRINT_KEY: string = 'lastFingerprint';
const SYNC_FOLDER: string = 'sync';
const MANIFEST_FILE: string = SYNC_FOLDER + '/manifest.json';
const FINGERPRINT_INTERVAL_MS: number = 45000;
const DIRTY_DEBOUNCE_MS: number = 15000;
const RETRY_DELAY_MS: number = 90000;
const MAX_SYNC_HISTORY_ITEMS: number = 1000;

interface RemoteSyncManifest {
  version: number;
  updatedAt: number;
  sections: string[];
}

interface RemoteSyncSection {
  name: string;
  data: string;
}

export class RemoteStorageSyncService {
  private context: common.UIAbilityContext | null = null;
  private timer: number = -1;
  private busy: boolean = false;
  private dirty: boolean = false;
  private started: boolean = false;
  private lastSyncAt: number = 0;
  private lastPulledAt: number = 0;
  private fingerprint: string = '';

  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.started = true;
    await this.loadState(context);
    await remoteStorageProfileStore.ensureLoaded(context);
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus('同步未启用', '在设置 → 下载 → 远程存储 中启用同步目录');
      return;
    }
    this.publishStatus(profile, '待同步', '');
    this.pullIfNewer(context, profile);
    this.schedule(FINGERPRINT_INTERVAL_MS);
  }

  pause(): void {
    this.started = false;
    this.clearTimer();
  }

  markDirty(): void {
    this.dirty = true;
    if (!this.started || this.busy) {
      return;
    }
    this.schedule(DIRTY_DEBOUNCE_MS);
  }

  async syncNow(): Promise<void> {
    const context = this.context;
    if (context === null || this.busy) {
      return;
    }
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus('同步未启用', '在设置 → 下载 → 远程存储 中启用同步目录');
      return;
    }
    this.busy = true;
    this.publishStatus(profile, '同步中…', '');
    try {
      const client = new WebDavClient(profile);
      const directory = await client.ensureDirectory(SYNC_FOLDER);
      if (!directory.ok) {
        throw new Error(directory.message);
      }
      const sections = await this.buildSections(context);
      for (let i = 0; i < sections.length; i++) {
        const uploaded = await client.putText(SYNC_FOLDER + '/' + sections[i].name + '.json', sections[i].data);
        if (!uploaded.ok) {
          throw new Error(sections[i].name + ': ' + uploaded.message);
        }
      }
      const manifest: RemoteSyncManifest = {
        version: 1,
        updatedAt: Date.now(),
        sections: sections.map((section: RemoteSyncSection): string => section.name)
      };
      const manifestUpload = await client.putText(MANIFEST_FILE, JSON.stringify(manifest));
      if (!manifestUpload.ok) {
        throw new Error(manifestUpload.message);
      }
      this.lastSyncAt = manifest.updatedAt;
      this.lastPulledAt = manifest.updatedAt;
      this.fingerprint = await this.computeFingerprint(context);
      await this.persistState(context);
      this.busy = false;
      this.dirty = false;
      logRemoteStorageInfo('sync completed sections=' + sections.length.toString());
      this.publishStatus(profile, '已同步 ' + syncTimeText(this.lastSyncAt), '');
      this.schedule(FINGERPRINT_INTERVAL_MS);
    } catch (error) {
      this.busy = false;
      const message = error instanceof Error ? error.message : String(error);
      logRemoteStorageWarn('sync failed: ' + message);
      this.publishStatus(profile, '离线，稍后重试', message);
      this.schedule(RETRY_DELAY_MS);
    }
  }

  private schedule(delayMs: number): void {
    if (!this.started) {
      return;
    }
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.tick();
    }, delayMs) as number;
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private async tick(): Promise<void> {
    const context = this.context;
    if (context === null || !this.started) {
      return;
    }
    const profile = remoteStorageProfileStore.profileForPurpose(REMOTE_STORAGE_PURPOSE_SYNC);
    if (profile === null) {
      this.setStatus('同步未启用', '在设置 → 下载 → 远程存储 中启用同步目录');
      return;
    }
    const fingerprint = await this.computeFingerprint(context);
    if (this.dirty || fingerprint !== this.fingerprint) {
      await this.syncNow();
      return;
    }
    this.schedule(FINGERPRINT_INTERVAL_MS);
  }

  private async buildSections(context: common.UIAbilityContext): Promise<RemoteSyncSection[]> {
    await Promise.all([
      ehSettingsStore.ensureLoaded(context),
      ehBookmarkStore.ensureLoaded(context),
      ehFilterStore.ensureLoaded(context),
      ehCommentBlacklistStore.ensureLoaded(context),
      ehSearchHistoryStore.load(context),
      ehBrowsePositionStore.ensureLoaded(context),
      ehHistoryStore.ensureLoaded(context)
    ]);
    const history: GalleryInfo[] = ehHistoryStore.getItems();
    const historySlice = history.length > MAX_SYNC_HISTORY_ITEMS ?
      history.slice(history.length - MAX_SYNC_HISTORY_ITEMS) : history;
    const sections: RemoteSyncSection[] = [
      { name: 'settings', data: JSON.stringify(ehSettingsStore.getTransferEntries()) },
      { name: 'bookmarks', data: JSON.stringify(ehBookmarkStore.getBackupItems()) },
      { name: 'filters', data: JSON.stringify(ehFilterStore.getRules()) },
      { name: 'blacklist', data: JSON.stringify(ehCommentBlacklistStore.getBackupItems()) },
      { name: 'searchHistory', data: JSON.stringify(ehSearchHistoryStore.getKeywords()) },
      { name: 'browsePositions', data: JSON.stringify(ehBrowsePositionStore.getBackupInfo()) },
      { name: 'readingProgress', data: JSON.stringify(ehHistoryStore.getReadingProgressBackupItems()) },
      { name: 'history', data: JSON.stringify(historySlice) }
    ];
    return sections;
  }

  private async pullIfNewer(context: common.UIAbilityContext, profile: RemoteStorageProfile): Promise<void> {
    try {
      const client = new WebDavClient(profile);
      const manifestResult = await client.getText(MANIFEST_FILE);
      if (!manifestResult.ok || manifestResult.text.length === 0) {
        return;
      }
      const manifest = JSON.parse(manifestResult.text) as RemoteSyncManifest;
      if (typeof manifest.updatedAt !== 'number' || manifest.updatedAt <= this.lastPulledAt) {
        return;
      }
      await Promise.all([
        ehSettingsStore.ensureLoaded(context),
        ehBookmarkStore.ensureLoaded(context),
        ehFilterStore.ensureLoaded(context),
        ehCommentBlacklistStore.ensureLoaded(context),
        ehSearchHistoryStore.load(context),
        ehBrowsePositionStore.ensureLoaded(context),
        ehHistoryStore.ensureLoaded(context)
      ]);
      for (let i = 0; i < manifest.sections.length; i++) {
        await this.applySection(context, client, manifest.sections[i]);
      }
      this.lastPulledAt = manifest.updatedAt;
      await this.persistState(context);
      logRemoteStorageInfo('sync pulled sections=' + manifest.sections.length.toString());
      this.publishStatus(profile, '已同步 ' + syncTimeText(this.lastSyncAt), '');
    } catch (error) {
      logRemoteStorageWarn('sync pull failed: ' + (error instanceof Error ? error.message : String(error)));
    }
  }

  private async applySection(context: common.UIAbilityContext, client: WebDavClient, name: string): Promise<void> {
    const file = await client.getText(SYNC_FOLDER + '/' + name + '.json');
    if (!file.ok || file.text.length === 0) {
      return;
    }
    try {
      if (name === 'settings') {
        ehSettingsStore.importEntries(JSON.parse(file.text) as SettingEntry[]);
        await ehSettingsStore.save(context);
      } else if (name === 'bookmarks') {
        ehBookmarkStore.importBackupItems(JSON.parse(file.text) as SearchBookmarkBackupInfo[]);
        await ehBookmarkStore.save(context);
      } else if (name === 'filters') {
        const rules = JSON.parse(file.text) as FilterRuleLike[];
        for (let i = 0; i < rules.length; i++) {
          const ruleMode = rules[i].mode;
          const ruleText = rules[i].text;
          if (typeof ruleText === 'string' && typeof ruleMode === 'number') {
            ehFilterStore.addRule(ruleMode, ruleText, rules[i].enabled !== false);
          }
        }
        await ehFilterStore.save(context);
      } else if (name === 'blacklist') {
        ehCommentBlacklistStore.importBackupItems(JSON.parse(file.text) as CommentBlacklistBackupEntry[]);
        await ehCommentBlacklistStore.save(context);
      } else if (name === 'searchHistory') {
        ehSearchHistoryStore.importKeywords(JSON.parse(file.text) as string[]);
        await ehSearchHistoryStore.save(context);
      } else if (name === 'browsePositions') {
        ehBrowsePositionStore.importBackupInfo(JSON.parse(file.text) as BrowsePositionsBackupInfo);
        await ehBrowsePositionStore.save(context);
      } else if (name === 'readingProgress') {
        ehHistoryStore.importReadingProgressBackupItems(JSON.parse(file.text) as ReadingProgressBackupInfo[]);
        await ehHistoryStore.save(context);
      } else if (name === 'history') {
        const items = JSON.parse(file.text) as GalleryInfo[];
        const limit = historyInfoSizeLimitFromValue(ehSettingsStore.getValue(HISTORY_INFO_SIZE_KEY, '100'));
        for (let i = 0; i < items.length; i++) {
          if (typeof items[i].gid === 'number' && items[i].gid > 0) {
            ehHistoryStore.addGallery(items[i], limit);
          }
        }
        await ehHistoryStore.save(context);
      }
    } catch (error) {
      logRemoteStorageError('sync section ' + name + ' apply failed: ' +
        (error instanceof Error ? error.message : String(error)));
    }
  }

  private async computeFingerprint(context: common.UIAbilityContext): Promise<string> {
    const historyLength = ehHistoryStore.getItems().length;
    const parts: string[] = [
      ehSettingsStore.getTransferEntries().length.toString(),
      ehBookmarkStore.getBackupItems().length.toString(),
      ehFilterStore.getRules().length.toString(),
      ehCommentBlacklistStore.getBackupItems().length.toString(),
      ehSearchHistoryStore.getKeywords().length.toString(),
      historyLength.toString(),
      remoteStorageProfileStore.getProfiles().length.toString()
    ];
    return parts.join(':');
  }

  private async loadState(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const lastSync = await prefs.get(LAST_SYNC_KEY, 0);
      const lastPull = await prefs.get(LAST_PULL_KEY, 0);
      const fingerprint = await prefs.get(FINGERPRINT_KEY, '');
      this.lastSyncAt = typeof lastSync === 'number' ? lastSync : 0;
      this.lastPulledAt = typeof lastPull === 'number' ? lastPull : 0;
      this.fingerprint = typeof fingerprint === 'string' ? fingerprint : '';
    } catch (error) {
    }
  }

  private async persistState(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(LAST_SYNC_KEY, this.lastSyncAt);
      await prefs.put(LAST_PULL_KEY, this.lastPulledAt);
      await prefs.put(FINGERPRINT_KEY, this.fingerprint);
      await prefs.flush();
    } catch (error) {
    }
  }

  private publishStatus(profile: RemoteStorageProfile, text: string, detail: string): void {
    this.setStatus(text, detail.length > 0 ? detail : ('服务器：' + profile.url));
  }

  private setStatus(text: string, detail: string): void {
    const revision = AppStorage.get<number>(REMOTE_SYNC_STATUS_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate<string>(REMOTE_SYNC_STATUS_TEXT_KEY, text);
    AppStorage.setOrCreate<string>(REMOTE_SYNC_STATUS_DETAIL_KEY, detail);
    AppStorage.setOrCreate<number>(REMOTE_SYNC_STATUS_REVISION_KEY, revision + 1);
  }
}

interface FilterRuleLike {
  mode?: number;
  text?: string;
  enabled?: boolean;
}

function syncTimeText(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date = new Date(timestamp);
  const hours = date.getHours();
  const minutes = date.getMinutes();
  return (hours < 10 ? '0' + hours.toString() : hours.toString()) + ':' +
    (minutes < 10 ? '0' + minutes.toString() : minutes.toString());
}

export const remoteStorageSyncService = new RemoteStorageSyncService();

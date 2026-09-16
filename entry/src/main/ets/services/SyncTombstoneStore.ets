import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  SyncTombstoneLike,
  SyncTombstoneSectionLike,
  mergeSyncTombstoneLists,
  pruneSyncTombstoneList
} from './RemoteStorageSupport';

const PREFERENCES_NAME: string = 'ehviewer_sync_tombstones';
const VALUES_KEY: string = 'sections';

interface StoredTombstones {
  version?: number;
  updatedAt?: number;
  sections?: SyncTombstoneSectionLike[];
}

// Records user deletions and re-adds per synced collection so other devices can propagate
// them instead of merging the removed item back. The newest operation per key wins.
export class SyncTombstoneStore {
  private sections: SyncTombstoneSectionLike[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveChain: Promise<void> = Promise.resolve();

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.loaded) {
      return;
    }
    if (this.loadPromise !== null) {
      await this.loadPromise;
      return;
    }
    this.loadPromise = this.loadNow(context);
    try {
      await this.loadPromise;
    } finally {
      this.loadPromise = null;
    }
  }

  private async loadNow(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '[]');
      const parsed = JSON.parse(typeof raw === 'string' ? raw : '[]') as StoredTombstones;
      this.sections = normalizeStoredSections(parsed.sections);
    } catch (error) {
      this.sections = [];
    }
    this.loaded = true;
  }

  list(section: string): SyncTombstoneLike[] {
    const records = this.sectionRecords(section);
    return records.slice();
  }

  isEmpty(): boolean {
    for (let i = 0; i < this.sections.length; i++) {
      if (this.sections[i].records.length > 0) {
        return false;
      }
    }
    return true;
  }

  recordDeletion(context: common.UIAbilityContext | undefined, section: string, key: string): void {
    this.record(context, section, key, false);
  }

  recordClear(context: common.UIAbilityContext | undefined, section: string, key: string): void {
    this.record(context, section, key, true);
  }

  private record(context: common.UIAbilityContext | undefined, section: string, key: string,
    cleared: boolean): void {
    const trimmed = key.trim();
    if (section.length === 0 || trimmed.length === 0) {
      return;
    }
    if (context !== undefined) {
      this.context = context;
    }
    const records = this.sectionRecords(section);
    const record: SyncTombstoneLike = {
      key: trimmed,
      deletedAt: Date.now(),
      cleared: cleared ? true : undefined
    };
    let replaced = false;
    for (let i = 0; i < records.length; i++) {
      if (records[i].key === trimmed) {
        if (records[i].deletedAt <= record.deletedAt) {
          records[i] = record;
        }
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      records.push(record);
    }
    this.queueSave();
  }

  serialize(): string {
    const payload: StoredTombstones = {
      version: 1,
      updatedAt: Date.now(),
      sections: this.sections
    };
    return JSON.stringify(payload);
  }

  mergeRemoteText(text: string): number {
    if (text.length === 0) {
      return 0;
    }
    let merged = 0;
    try {
      const parsed = JSON.parse(text) as StoredTombstones;
      const remoteSections = normalizeStoredSections(parsed.sections);
      for (let i = 0; i < remoteSections.length; i++) {
        const remote = remoteSections[i];
        const local = this.sectionRecords(remote.name);
        const next = mergeSyncTombstoneLists(local, remote.records);
        if (JSON.stringify(next) !== JSON.stringify(local)) {
          merged++;
        }
        this.setSectionRecords(remote.name, next);
      }
    } catch (error) {
      return 0;
    }
    if (merged > 0) {
      this.queueSave();
    }
    return merged;
  }

  prune(maxAgeMs: number): void {
    const now = Date.now();
    const next: SyncTombstoneSectionLike[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      const records = pruneSyncTombstoneList(this.sections[i].records, now, maxAgeMs);
      if (records.length > 0) {
        next.push({ name: this.sections[i].name, records: records });
      }
    }
    this.sections = next;
    this.queueSave();
  }

  private sectionRecords(section: string): SyncTombstoneLike[] {
    for (let i = 0; i < this.sections.length; i++) {
      if (this.sections[i].name === section) {
        return this.sections[i].records;
      }
    }
    const records: SyncTombstoneLike[] = [];
    this.sections.push({ name: section, records: records });
    return records;
  }

  private setSectionRecords(section: string, records: SyncTombstoneLike[]): void {
    for (let i = 0; i < this.sections.length; i++) {
      if (this.sections[i].name === section) {
        this.sections[i].records = records;
        return;
      }
    }
    if (records.length > 0) {
      this.sections.push({ name: section, records: records });
    }
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    const snapshot = this.serialize();
    this.saveChain = this.saveChain.then(async () => {
      await this.saveSnapshot(context, snapshot);
    }).catch(() => {
    });
  }

  private async saveSnapshot(context: common.UIAbilityContext, payload: string): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, payload);
      await prefs.flush();
    } catch (error) {
    }
  }
}

function normalizeStoredSections(sections: SyncTombstoneSectionLike[] | undefined): SyncTombstoneSectionLike[] {
  const next: SyncTombstoneSectionLike[] = [];
  if (!Array.isArray(sections)) {
    return next;
  }
  for (let i = 0; i < sections.length; i++) {
    const section = sections[i];
    if (section === null || typeof section.name !== 'string' || section.name.length === 0 ||
      !Array.isArray(section.records)) {
      continue;
    }
    const records: SyncTombstoneLike[] = [];
    for (let j = 0; j < section.records.length; j++) {
      const record = section.records[j];
      if (record !== null && typeof record.key === 'string' && record.key.length > 0 &&
        typeof record.deletedAt === 'number') {
        records.push({
          key: record.key,
          deletedAt: record.deletedAt,
          cleared: record.cleared === true ? true : undefined
        });
      }
    }
    if (records.length > 0) {
      next.push({ name: section.name, records: records });
    }
  }
  return next;
}

export const syncTombstoneStore: SyncTombstoneStore = new SyncTombstoneStore();

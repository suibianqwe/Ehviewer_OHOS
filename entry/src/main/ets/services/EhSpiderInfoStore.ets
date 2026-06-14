import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GallerySite } from '../model/GalleryModels';

const PREFERENCES_NAME: string = 'ehviewer_spider_info';
const VALUES_KEY: string = 'entries';
const MAX_ENTRIES: number = 128;
const MAX_PAGE_TOKENS: number = 240;
const ENTRY_TTL_MS: number = 7 * 24 * 60 * 60 * 1000;

export interface SpiderPageTokenEntry {
  pageIndex: number;
  pageToken: string;
}

export interface SpiderInfoEntry {
  key: string;
  site: number;
  gid: number;
  showKey: string;
  pageTokens: SpiderPageTokenEntry[];
  updatedAt: number;
}

interface StoredSpiderInfoEntry {
  key?: string;
  site?: number;
  gid?: number;
  showKey?: string;
  pageTokens?: SpiderPageTokenEntry[];
  updatedAt?: number;
}

export class EhSpiderInfoStore {
  private entries: SpiderInfoEntry[] = [];
  private context: common.UIAbilityContext | null = null;

  async load(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        this.entries = [];
        return;
      }

      const parsed = JSON.parse(raw) as StoredSpiderInfoEntry[];
      if (!Array.isArray(parsed)) {
        this.entries = [];
        return;
      }

      const loaded: SpiderInfoEntry[] = [];
      const now = Date.now();
      for (let i = 0; i < parsed.length; i++) {
        const entry = normalizeEntry(parsed[i]);
        if (entry !== null && now - entry.updatedAt <= ENTRY_TTL_MS) {
          loaded.push(entry);
        }
      }
      this.entries = loaded.slice(0, MAX_ENTRIES);
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

  getShowKey(site: GallerySite, gid: number): string {
    const entry = this.getEntry(site, gid);
    return entry === null ? '' : entry.showKey;
  }

  putShowKey(site: GallerySite, gid: number, showKey: string): void {
    const key = spiderInfoKey(site, gid);
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].key === key) {
        if (showKey.length === 0) {
          this.entries.splice(i, 1);
        } else {
          this.entries[i].showKey = showKey;
          this.entries[i].updatedAt = Date.now();
          this.promote(i);
        }
        this.persistQuietly();
        return;
      }
    }

    if (showKey.length > 0) {
      this.entries.unshift({
        key: key,
        site: Number(site),
        gid: gid,
        showKey: showKey,
        pageTokens: [],
        updatedAt: Date.now()
      });
      this.trim();
      this.persistQuietly();
    }
  }

  putPageToken(site: GallerySite, gid: number, pageIndex: number, pageToken: string): void {
    if (pageToken.length === 0 || pageIndex < 0) {
      return;
    }

    let entry = this.getEntry(site, gid);
    if (entry === null) {
      entry = {
        key: spiderInfoKey(site, gid),
        site: Number(site),
        gid: gid,
        showKey: '',
        pageTokens: [],
        updatedAt: Date.now()
      };
      this.entries.unshift(entry);
    }

    let updated = false;
    for (let i = 0; i < entry.pageTokens.length; i++) {
      if (entry.pageTokens[i].pageIndex === pageIndex) {
        entry.pageTokens[i].pageToken = pageToken;
        updated = true;
        break;
      }
    }
    if (!updated) {
      entry.pageTokens.push({ pageIndex: pageIndex, pageToken: pageToken });
    }

    entry.updatedAt = Date.now();
    if (entry.pageTokens.length > MAX_PAGE_TOKENS) {
      entry.pageTokens.splice(0, entry.pageTokens.length - MAX_PAGE_TOKENS);
    }
    this.trim();
    this.persistQuietly();
  }

  private getEntry(site: GallerySite, gid: number): SpiderInfoEntry | null {
    const key = spiderInfoKey(site, gid);
    const now = Date.now();
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i];
      if (entry.key === key) {
        if (now - entry.updatedAt > ENTRY_TTL_MS) {
          this.entries.splice(i, 1);
          this.persistQuietly();
          return null;
        }
        this.promote(i);
        return entry;
      }
    }
    return null;
  }

  private promote(index: number): void {
    if (index <= 0 || index >= this.entries.length) {
      return;
    }
    const entry = this.entries[index];
    this.entries.splice(index, 1);
    this.entries.unshift(entry);
  }

  private trim(): void {
    while (this.entries.length > MAX_ENTRIES) {
      this.entries.pop();
    }
  }

  private persistQuietly(): void {
    if (this.context === null) {
      return;
    }
    this.save(this.context).catch(() => {});
  }
}

function normalizeEntry(raw: StoredSpiderInfoEntry): SpiderInfoEntry | null {
  if (typeof raw.key !== 'string' || typeof raw.site !== 'number' || typeof raw.gid !== 'number' ||
    typeof raw.showKey !== 'string' || typeof raw.updatedAt !== 'number') {
    return null;
  }

  const tokens: SpiderPageTokenEntry[] = [];
  if (Array.isArray(raw.pageTokens)) {
    for (let i = 0; i < raw.pageTokens.length; i++) {
      const token = raw.pageTokens[i];
      if (typeof token.pageIndex === 'number' && typeof token.pageToken === 'string') {
        tokens.push({ pageIndex: token.pageIndex, pageToken: token.pageToken });
      }
    }
  }

  return {
    key: raw.key,
    site: raw.site,
    gid: raw.gid,
    showKey: raw.showKey,
    pageTokens: tokens.slice(0, MAX_PAGE_TOKENS),
    updatedAt: raw.updatedAt
  };
}

function spiderInfoKey(site: GallerySite, gid: number): string {
  return Number(site).toString() + ':' + gid.toString();
}

export const ehSpiderInfoStore: EhSpiderInfoStore = new EhSpiderInfoStore();

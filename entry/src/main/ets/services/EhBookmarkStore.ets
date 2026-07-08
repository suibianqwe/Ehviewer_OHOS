import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { GalleryCategory, GalleryRoute } from '../model/GalleryModels';
import { DEFAULT_ADVANCE_SEARCH, ListMode } from './EhUrl';

const PREFERENCES_NAME: string = 'ehviewer_bookmarks';
const VALUES_KEY: string = 'items';

export interface SearchBookmarkBackupInfo {
  id?: string;
  name?: string;
  mode?: number;
  category?: number;
  keyword?: string;
  advanceSearch?: number;
  minRating?: number;
  pageFrom?: number;
  pageTo?: number;
  filterEnabled?: boolean;
  location?: string;
  time?: number;
}

export interface SearchBookmarkInfo {
  id: string;
  name: string;
  mode: ListMode;
  category: number;
  keyword: string;
  advanceSearch: number;
  minRating: number;
  pageFrom: number;
  pageTo: number;
  filterEnabled: boolean;
  location: GalleryRoute;
  time: number;
}

export class EhBookmarkStore {
  private items: SearchBookmarkInfo[] = [];
  private context: common.UIAbilityContext | undefined = undefined;
  private loaded: boolean = false;
  private loadPromise: Promise<void> | null = null;
  private saveChain: Promise<void> = Promise.resolve();

  async ensureLoaded(context: common.UIAbilityContext): Promise<void> {
    if (this.loaded) {
      this.context = context;
      return;
    }
    if (this.loadPromise !== null) {
      return this.loadPromise;
    }
    this.context = context;
    this.loadPromise = this.load(context);
    return this.loadPromise;
  }

  getItems(): SearchBookmarkInfo[] {
    return cloneBookmarks(this.items);
  }

  getBackupItems(): SearchBookmarkBackupInfo[] {
    return this.items.map((item: SearchBookmarkInfo): SearchBookmarkBackupInfo => bookmarkToBackup(item));
  }

  addBookmark(bookmark: SearchBookmarkInfo): boolean {
    const normalized = normalizeBookmark(bookmark);
    if (normalized === null || this.hasEquivalent(normalized) || this.hasName(normalized.name)) {
      return false;
    }
    const next = cloneBookmarks(this.items);
    next.push(normalized);
    next.sort((left: SearchBookmarkInfo, right: SearchBookmarkInfo): number => left.time - right.time);
    this.items = next;
    this.queueSave();
    return true;
  }

  importBookmark(bookmark: SearchBookmarkBackupInfo): boolean {
    const normalized = backupToBookmark(bookmark);
    if (normalized === null || this.hasEquivalent(normalized)) {
      return false;
    }
    if (this.hasName(normalized.name)) {
      normalized.name = uniqueBookmarkName(normalized.name, this.items);
    }
    const next = cloneBookmarks(this.items);
    next.push(normalized);
    next.sort((left: SearchBookmarkInfo, right: SearchBookmarkInfo): number => left.time - right.time);
    this.items = next;
    return true;
  }

  importBackupItems(items: SearchBookmarkBackupInfo[]): number {
    let count = 0;
    for (let i = 0; i < items.length; i++) {
      if (this.importBookmark(items[i])) {
        count++;
      }
    }
    this.queueSave();
    return count;
  }

  removeBookmark(id: string): void {
    const next: SearchBookmarkInfo[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id !== id) {
        next.push(cloneBookmark(this.items[i]));
      }
    }
    this.items = next;
    this.queueSave();
  }

  renameBookmark(id: string, name: string): boolean {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const next = cloneBookmarks(this.items);
    for (let i = 0; i < next.length; i++) {
      if (next[i].id !== id && next[i].name === trimmed) {
        return false;
      }
    }
    let changed = false;
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i].name = trimmed;
        changed = true;
        break;
      }
    }
    if (!changed) {
      return false;
    }
    this.items = next;
    this.queueSave();
    return true;
  }

  moveBookmarkToIndex(from: number, to: number): boolean {
    const next = cloneBookmarks(this.items);
    if (from < 0 || from >= next.length || to < 0 || to >= next.length || from === to) {
      return false;
    }
    const removed = next.splice(from, 1);
    if (removed.length === 0) {
      return false;
    }
    const moving = removed[0];
    next.splice(to, 0, moving);
    const now = Date.now();
    for (let i = 0; i < next.length; i++) {
      next[i].time = now + i;
    }
    this.items = next;
    this.queueSave();
    return true;
  }

  createBookmark(name: string, mode: ListMode, category: number, keyword: string, advanceSearch: number,
    minRating: number, pageFrom: number, pageTo: number, filterEnabled: boolean = true,
    location: GalleryRoute = GalleryRoute.Home): SearchBookmarkInfo {
    return {
      id: 'bookmark_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString(),
      name: name,
      mode: mode,
      category: category,
      keyword: keyword,
      advanceSearch: advanceSearch,
      minRating: minRating,
      pageFrom: pageFrom,
      pageTo: pageTo,
      filterEnabled: filterEnabled,
      location: normalizeBookmarkLocation(location),
      time: Date.now()
    };
  }

  hasEquivalent(bookmark: SearchBookmarkInfo): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (bookmarksEquivalent(this.items[i], bookmark)) {
        return true;
      }
    }
    return false;
  }

  hasName(name: string): boolean {
    const normalized = name.trim();
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].name === normalized) {
        return true;
      }
    }
    return false;
  }

  async save(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    await this.saveSnapshot(context, this.getBackupItems());
  }

  private async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const raw = await prefs.get(VALUES_KEY, '[]');
      const text = typeof raw === 'string' ? raw : '[]';
      const parsed = JSON.parse(text) as SearchBookmarkBackupInfo[];
      const next: SearchBookmarkInfo[] = [];
      if (Array.isArray(parsed)) {
        for (let i = 0; i < parsed.length; i++) {
          const item = backupToBookmark(parsed[i]);
          if (item !== null && !bookmarkListHasEquivalent(next, item)) {
            next.push(item);
          }
        }
      }
      next.sort((left: SearchBookmarkInfo, right: SearchBookmarkInfo): number => left.time - right.time);
      this.items = next;
    } catch (error) {
      this.items = [];
    }
    this.loaded = true;
    this.loadPromise = null;
  }

  private queueSave(): void {
    const context = this.context;
    if (context === undefined || !this.loaded) {
      return;
    }
    const snapshot = this.getBackupItems();
    this.saveChain = this.saveChain.then(async () => {
      await this.saveSnapshot(context, snapshot);
    }).catch(() => {});
  }

  private async saveSnapshot(context: common.UIAbilityContext, snapshot: SearchBookmarkBackupInfo[]): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      await prefs.put(VALUES_KEY, JSON.stringify(snapshot));
      await prefs.flush();
    } catch (error) {
      throw new Error(String(error));
    }
  }
}

export function defaultBookmarkName(mode: ListMode, category: number, keyword: string, advanceSearch: number,
  minRating: number, pageFrom: number, pageTo: number): string {
  const trimmed = keyword.trim();
  if (mode === ListMode.Subscription && trimmed.length === 0 && isPlainSearch(category, advanceSearch, minRating,
    pageFrom, pageTo)) {
    return 'Subscription';
  }
  if (mode === ListMode.WhatsHot) {
    return 'Whats Hot';
  }
  if (trimmed.length > 0) {
    return trimmed;
  }
  if (category !== GalleryCategory.None) {
    return 'Category ' + category.toString();
  }
  return 'Homepage';
}

function isPlainSearch(category: number, advanceSearch: number, minRating: number, pageFrom: number,
  pageTo: number): boolean {
  return category === GalleryCategory.None && advanceSearch === -1 && minRating === -1 && pageFrom === -1 &&
    pageTo === -1;
}

function backupToBookmark(stored: SearchBookmarkBackupInfo): SearchBookmarkInfo | null {
  const mode = typeof stored.mode === 'number' ? stored.mode as number : ListMode.Normal;
  const category = typeof stored.category === 'number' ? stored.category as number : GalleryCategory.None;
  const keyword = typeof stored.keyword === 'string' ? stored.keyword as string : '';
  const advanceSearch = typeof stored.advanceSearch === 'number' ? stored.advanceSearch as number : -1;
  const minRating = typeof stored.minRating === 'number' ? stored.minRating as number : -1;
  const pageFrom = typeof stored.pageFrom === 'number' ? stored.pageFrom as number : -1;
  const pageTo = typeof stored.pageTo === 'number' ? stored.pageTo as number : -1;
  const filterEnabled = typeof stored.filterEnabled === 'boolean' ? stored.filterEnabled as boolean : true;
  const location = normalizeBookmarkLocation(typeof stored.location === 'string' ? stored.location as string :
    locationForMode(mode));
  const fallbackName = defaultBookmarkName(mode, category, keyword, advanceSearch, minRating, pageFrom, pageTo);
  const name = typeof stored.name === 'string' && stored.name.trim().length > 0 ? stored.name.trim() : fallbackName;
  return normalizeBookmark({
    id: typeof stored.id === 'string' && stored.id.length > 0 ? stored.id :
      'bookmark_' + (typeof stored.time === 'number' ? stored.time as number : Date.now()).toString() + '_' +
        Math.floor(Math.random() * 100000).toString(),
    name: name,
    mode: normalizeBookmarkMode(mode),
    category: category,
    keyword: keyword,
    advanceSearch: advanceSearch,
    minRating: minRating,
    pageFrom: pageFrom,
    pageTo: pageTo,
    filterEnabled: filterEnabled,
    location: location,
    time: typeof stored.time === 'number' ? stored.time as number : Date.now()
  });
}

function normalizeBookmark(bookmark: SearchBookmarkInfo): SearchBookmarkInfo | null {
  if (bookmark.name.trim().length === 0 || bookmark.mode === ListMode.ImageSearch) {
    return null;
  }
  return {
    id: bookmark.id.length > 0 ? bookmark.id : 'bookmark_' + Date.now().toString(),
    name: bookmark.name.trim(),
    mode: normalizeBookmarkMode(bookmark.mode),
    category: typeof bookmark.category === 'number' ? bookmark.category : GalleryCategory.None,
    keyword: bookmark.keyword.trim(),
    advanceSearch: typeof bookmark.advanceSearch === 'number' ? bookmark.advanceSearch : DEFAULT_ADVANCE_SEARCH,
    minRating: typeof bookmark.minRating === 'number' ? bookmark.minRating : -1,
    pageFrom: typeof bookmark.pageFrom === 'number' ? bookmark.pageFrom : -1,
    pageTo: typeof bookmark.pageTo === 'number' ? bookmark.pageTo : -1,
    filterEnabled: bookmark.filterEnabled !== false,
    location: normalizeBookmarkLocation(bookmark.location),
    time: typeof bookmark.time === 'number' ? bookmark.time : Date.now()
  };
}

function normalizeBookmarkMode(mode: number): ListMode {
  if (mode === ListMode.Uploader || mode === ListMode.Tag || mode === ListMode.WhatsHot ||
    mode === ListMode.Subscription || mode === ListMode.Filter || mode === ListMode.TopList) {
    return mode;
  }
  return ListMode.Normal;
}

function bookmarkToBackup(item: SearchBookmarkInfo): SearchBookmarkBackupInfo {
  return {
    id: item.id,
    name: item.name,
    mode: item.mode,
    category: item.category,
    keyword: item.keyword,
    advanceSearch: item.advanceSearch,
    minRating: item.minRating,
    pageFrom: item.pageFrom,
    pageTo: item.pageTo,
    filterEnabled: item.filterEnabled,
    location: item.location,
    time: item.time
  };
}

function cloneBookmarks(items: SearchBookmarkInfo[]): SearchBookmarkInfo[] {
  const result: SearchBookmarkInfo[] = [];
  for (let i = 0; i < items.length; i++) {
    result.push(cloneBookmark(items[i]));
  }
  return result;
}

function cloneBookmark(item: SearchBookmarkInfo): SearchBookmarkInfo {
  return {
    id: item.id,
    name: item.name,
    mode: item.mode,
    category: item.category,
    keyword: item.keyword,
    advanceSearch: item.advanceSearch,
    minRating: item.minRating,
    pageFrom: item.pageFrom,
    pageTo: item.pageTo,
    filterEnabled: item.filterEnabled,
    location: item.location,
    time: item.time
  };
}

function bookmarkListHasEquivalent(items: SearchBookmarkInfo[], bookmark: SearchBookmarkInfo): boolean {
  for (let i = 0; i < items.length; i++) {
    if (bookmarksEquivalent(items[i], bookmark)) {
      return true;
    }
  }
  return false;
}

function bookmarksEquivalent(left: SearchBookmarkInfo, right: SearchBookmarkInfo): boolean {
  return left.mode === right.mode && left.category === right.category && left.keyword === right.keyword &&
    left.advanceSearch === right.advanceSearch && left.minRating === right.minRating &&
    left.pageFrom === right.pageFrom && left.pageTo === right.pageTo &&
    left.filterEnabled === right.filterEnabled && left.location === right.location;
}

function normalizeBookmarkLocation(location: GalleryRoute | string): GalleryRoute {
  if (location === GalleryRoute.Subscription || location === 'subscription') {
    return GalleryRoute.Subscription;
  }
  if (location === GalleryRoute.WhatsHot || location === 'whats_hot') {
    return GalleryRoute.WhatsHot;
  }
  return GalleryRoute.Home;
}

function locationForMode(mode: number): GalleryRoute {
  if (mode === ListMode.Subscription) {
    return GalleryRoute.Subscription;
  }
  if (mode === ListMode.WhatsHot) {
    return GalleryRoute.WhatsHot;
  }
  return GalleryRoute.Home;
}

function uniqueBookmarkName(name: string, existing: SearchBookmarkInfo[]): string {
  let candidate = name;
  let suffix = 2;
  while (bookmarkNameExists(candidate, existing)) {
    candidate = name + ' ' + suffix.toString();
    suffix++;
  }
  return candidate;
}

function bookmarkNameExists(name: string, existing: SearchBookmarkInfo[]): boolean {
  for (let i = 0; i < existing.length; i++) {
    if (existing[i].name === name) {
      return true;
    }
  }
  return false;
}

export const ehBookmarkStore: EhBookmarkStore = new EhBookmarkStore();
